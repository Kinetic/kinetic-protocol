# Overview
Kinetic is a key-value storage system. A Kinetic Device (e.g. a Kinetic Drive or a traditional server running the Java Reference Implementation) stores key-value objects. Kinetic Client applications can communicate with a Kinetic Device by sending messages over a network using TCP. Each individual message is called a “Kinetic Protocol Data Unit” (Kinetic PDU) and represents an individual request or response. For example, a Kinetic Client may send a message requesting the value associated with a particular key to a Kinetic Device. The device would respond with a message containing the value. 

## Document Assumptions
This document describes the structure of Protocol Buffer messages in detail. It is important to have a familiarity with the Protocol Buffer data interchange format ([https://code.google.com/p/protobuf/](https://code.google.com/p/protobuf/)). Where data types are specified with respect to fields in `protobuf` messages, the Scalar Value Types documented here: [https://developers.google.com/protocol-buffers/docs/proto](https://developers.google.com/protocol-buffers/docs/proto) will be used.

## Table of Contents

- [Overview](#user-content-overview)
    - [Document Assumptions](#user-content-document-assumptions)
- [Kinetic Protocol Data Unit Structure](#user-content-kinetic-protocol-data-unit-structure)
        - [Protobuf Structure](#user-content-protobuf-structure)
- [Access Control](#user-content-access-control)
    - [Examples](#user-content-examples)
        - [Client 1](#user-content-client-1)
        - [Client 2](#user-content-client-2)
- [Operation Details](#user-content-operation-details)
    - [Overview](#user-content-overview-1)
    - [Cross-Cutting Concerns](#user-content-cross-cutting-concerns)
        - [Error Cases](#user-content-error-cases)
    - [No Op](#user-content-no-op)
    - [Modify Value Operations](#user-content-modify-value-operations)
        - [Cross-Cutting Concerns](#user-content-cross-cutting-concerns-1)
        - [PUT](#user-content-put)
        - [Delete](#user-content-delete)
        - [Flush](#user-content-flush)
    - [Read Operations](#user-content-read-operations)
        - [Cross-Cutting Concenrs](#user-content-cross-cutting-concenrs)
        - [GET](#user-content-get)
        - [Get Version](#user-content-get-version)
        - [Get Next](#user-content-get-next)
        - [Get Previous](#user-content-get-previous)
        - [Get Key Range](#user-content-get-key-range)
    - [Setup](#user-content-setup)
        - [Set Cluster Version](#user-content-set-cluster-version)
        - [Firmware Download](#user-content-firmware-download)
    - [Administration](#user-content-administration)
        - [Set Pin](#user-content-set-pin)
        - [Lock and Unlock](#user-content-lock-and-unlock)
        - [Instant Secure Erase](#user-content-instant-secure-erase)
        - [ACL Setup](#user-content-acl-setup)
        - [Get Log](#user-content-get-log)
    - [Peer to Peer](#user-content-peer-to-peer)
    - [Batch Operation](#user-content-batch-operation)

_Table of Contents generated with [DocToc](http://doctoc.herokuapp.com/)_

# Kinetic Protocol Data Unit Structure
A Kinetic Protocol Data Unit is composed of a Protocol Buffer (`protobuf`) message, containing operation metadata & key-value metadata, and the value. It is important to note that the value is not encoded in the `protobuf` message; it is a separate top-level component of the Kinetic PDU. 

Specifically, a Kinetic PDU is structured as follows: 


| Offset | Type | Length |  Description |
| ------ | ------ | ---- |----------- |
| 0 | Byte | 1 Byte | Version prefix: currently the character ‘F’, denoting the beginning of the message. (The character ‘F’, the Hex value 46). |
| 1 | 4 Byte Big Endian Integer |4 Bytes | The number of bytes in the `protobuf` message (the maximum length for `protobuf` messages is 1024*1024 bytes).|
| 5 | 4 Byte Big Endian Integer| 4 Bytes | The number of bytes in the value (the maximum length for values is 1024*1024 bytes).|
| 9 | Bytes |<= 1024*1024 Bytes | The `protobuf` message. |
| 9 + length of `protobuf` message | Bytes | <= 1024*1024 Bytes | The value. |


### Protobuf Structure
Within a Kinetic PDU, the `protobuf` message encodes the specifics of the requested operation (or response).  At a high level, each `protobuf` message contains:

- A required AuthType that indicates the authentication type of the Kinetic PDU message.  
- An optional HMACauth that contains userId and HMAC of the byte representation of the Command.
- An optional PINauth that contains byte representation of the pin.
- a commandBytes field that contains the `protobuf` byte representation of the Command.

Each Command contains a:

- Header, containing metadata about the message such as type (e.g. GET, GET_RESPONSE, PUT, PUT_RESPONSE, etc)
- Body, containing operation-specific information, such as key-value information for PUT or key range information for GETKEYRANGE.
- Status, containing information about whether an associated operation succeeded or failed (and why).

The message structure for each operation will be described in depth in the following sections. 

# Access Control
The Kinetic Protocol supports restricting the operations a requester (identity) can perform by way of Access Control Lists (ACLs). They are structured as follows:

```
	message ACL {
	    // The same identity specified in the header of messages
		optional int64 identity = 1;

		// This is the identity's HMAC Key. This is a shared secret between the
		// client and the device, used to sign requests.
		optional bytes key = 2;

		// This is the algorithm used for performing the HMAC for messages for 
		// this identity.
		// The supported values are: HmacSHA1.
	    optional HMACAlgorithm hmacAlgorithm = 3;
	
		// Scope is the core of an ACL, an identity can have several.
		// See below.
		repeated Scope scope = 4;

		// Scopes grant a set of permissions to the identity associated
		// with the ACL. Scopes can further restrict which situations
		// those permissions apply to by using the offset, value,
		// and TlsRequired fields
		message Scope {
			// Offset and value should be used to restrict 
			// which keys the Scope applies to. For any given offset and value, 
      // the permission will only apply to keys that match the value at 
      // the given offset. This is analogous to a substring match in many 
      // languages, where the key in question is the target.
			optional uint64 offset = 1;
			optional bytes value = 2;
			
			// The Permission being granted.
			// There can be many, there must be at least one.
			repeated Permission permission = 3;
			
			// When set to true, this scope only applies to SSL connections.
			// Even if an identity has an ACL with a scope containing a specific
			// permission, if that permission belongs to a scope for which
			// TlsRequired is true and the identity makes a non-ssl request,
			// Kinetic will behave as if the identity does not have that
			// permission.
			optional bool TlsRequired = 4; 
		}

		// These are the permissions that can be included in a scope
		enum Permission {
			INVALID = -1; // place holder for backward compatibility
			READ = 0; // can read key/values
			WRITE = 1; // can write key/values
			DELETE = 2; // can delete key/values
			RANGE = 3; // can do a range
			SETUP = 4; // can set up a device
			P2POP = 5; // can do a peer to peer operation
			GETLOG = 7; // can get log
			SECURITY = 8; // can set up the security permission of the device
		}

		// Currently only one valid HMAC algorithm is supported
		enum HMACAlgorithm {
           // Added to allow additional HmacAlgorithms without breaking 
           // backward compatibility.
           Unknown = 0; 
           HmacSHA1 = 1; 
        }

	}

```

See the Security section below for details on setting ACLs. 

## Examples
In this section we'll give some concrete examples of how ACLs can be used. 

###Client 1

Suppose client 1 has an ACL like so:

```
ACL {
	identity: 1
	key: "a3b38c37298f7f01a377518dae81dd99655b2be8129c3b2c6357b7e779064159"
	HMACAlgorithm: HmacSHA1
	
	// There can be multiple scopes, we'll show that in these examples by
	// repeated scope objects like this
	scope {
		permission: READ
	}

	scope {
		offset: 0
		value: "foo"
		permission: WRITE
	}
}
```

Client 1 would be able to `GET` any object in the store, but only `PUT` keys that start with "foo".

###Client 2

Suppose client 2 has an ACL like so:

```
ACL {
	identity: 2
	key: "13010b8d8acdbe6abc005840aad1dc5dedb4345e681ed4e3c4645d891241d6b2"
	HMACAlgorithm: HmacSHA1	
	
	scope {
		permission: SECURITY
		TlsRequired: true
	}
}
```

Client 2 would be able to create new identities and set ACLs (using the Security operation) but only over SSL connections. Client 2 would not be able to read or write any keys on the device (though they could reset their own ACL to allow such activity).



	

# Operation Details

## Overview
This section describes the `protobuf` message structure for each operation supported by the Kinetic protocol. There are many fields that may be set on all requests, to simplify this document those will be documented once in the Cross-Cutting Concerns section. Within each logical grouping of operations (read value, modify value, etc) there are additional common fields. We will begin each sub-section with a description of common fields.

## Cross-Cutting Concerns
There are many fields in the `protobuf` message which can be specified on many operations. Instead of repeating the documentation for those fields for each call, we will show them here.

**Request Message**

```
Message {
  // required AuthType
  // Every message must be one of the defined enum auth types (HMACAUTH|PINAUTH|UNSOLICITEDSTATUS).
  authType: ...
  
  // Normal messages uses this auth type
  hmacAuth: ...
  
  // for Pin based operations. These include device lock, unlock and erase
  pinAuth: ...
  
  // required bytes
  // the embedded message providing the request (for HMACauth) and
  // the response (for all auth types).
  // the protocol buffer Command message is encoded/decoded to/from the commandBytes bytes
  commandBytes: ...

  // The Message Type determines how the the message is to be processed.
  enum AuthType {
    // This is for normal traffic. Check the HMAC of the command and
    // if correct, process the command.
    HMACAUTH: ...

    // device lock, unlock and erase commands. These must come over the TLS connection.
    // If they do not, close the connection. If it is over
    // the TLS connection, execute the pin operation.
    PINAUTH: ...

    // In the event that the device is going to close the connection, an
    // unsolicited status will be returned first.
    UNSOLICITEDSTATUS = 3;
  }

  // This is for normal message to the device
  // and for responses. These are allowed once the
  // device is unlocked. The HMAC provides for
  // authenticity, Integrity and to enforce roles.
  message HMACauth {
    // The "identity" identifies the requester and the key and algorithm to
    // be used for hmac.
    identity: ...
    
    // The HMAC of this message used to verify integrity. 
    // The HMAC is taken of the byte-representation of the Command message of this 
    // protobuf message. An identity-specific shared secret is used to compute the HMAC.
    // The Kinetic Device must have the key associated with the identity in
    // this HMACauth message.
    // For example, in pseudocode where a computeHMAC function exists which takes 
    // a value and an algorithm:
    //	 hmac = computeHMAC(message.command.toBytes(), identityHMACAlgorithm)
    hmac: ...
  }

  // Pin based authentication for Pin operations.
  message PINauth {
    // The pin necessary to make the operations valid
    pin: ...
  }
}

Command {
  header {
    // The version number of this cluster definition. If this is not equal to 
    // the value on the device, the request is rejected and will return a 
    // `VERSION_FAILURE` `statusCode` in the `Status` message. By default this 
    // value is 0, allowing systems not using cluster versioning to ignore this
    // field in the header and setup.
    clusterVersion: ...

    // A unique number for this connection between the source and target. 
    // The drive can change this number and the client must continue to use the 
    // new number and the number must remain constant during the session.
    connectionID: ...

    // Sequence is a monotonically increasing number for each request in a TCP 
    // connection. 
    sequence: ...

    // The message type identifies which sort of operation this is.
    // See the MessageType enum in the protobuf definition for all potential 
    // values.
    // Note that the *_RESPONSE message types are reserved for messages from
    // the Kinetic Device to the client (i.e. responses).
    messageType: ...
  }
  body {
	// Omitted in this cross-cutting documentation section
  }
}
```

**Response Message**

```
Message {
  // see request message above.
  authType: ...
  
  // see request message above
  hmacAuth: ...
  
  // the protocol buffer Command message is encoded/decoded to/from the commandBytes bytes
  // see request message above
  commandBytes: ...
}
  
Command {
  header {
    // In a response message, ackSequence will be the same as the 
    // sequence value set in the request message.
    // The client can use this to map async responses to their
    // associated requests. 
    // This is important because operations within a connection may be reordered.
    ackSequence: ...
    
    // In a response, messageType corresponds to the requested messageType.
    // For instance, requests with a PUT messageType will receive a response 
    // with a PUT_RESPONSE messageType.
    messageType: ...
  }
  body {
	// Omitted in this cross-cutting documentation section
  }
  status {
    // Every response from the Kinetic Device will specify a code indicating 
    // whether the request was successful, or the specific error case 
    // encountered. The full list of codes is specified by the 
    // Status.StatusCode enum.
    code: SUCCESS
  }
}

```

### Error Cases
When an error occurs on the Kinetic Device, the response message includes a `status` with a `code`. These codes are enumerated in the `StatusCode` enum in the protocol definition. They will be discussed here in more detail.

* `INTERNAL_ERROR` indicates that the Kinetic Device experiences a malfunction. (Currently this code is returned in certain cases that don't indicate a drive malfunction, these will be updated.) 
* `HMAC_FAILURE` indicates that the HMAC of the request is incorrect or missing. This will also be returned when an unknown identity is set in the header, since the device cannot verify an HMAC for an unknown identity.
* `NOT_AUTHORIZED` indicates the attempted operation could not be completed because the identity set in the header did not have authorization.
* `VERSION_FAILURE` indicates that the `clusterVersion` of the Kinetic Device does not match the `clusterVersion` set in the header of the requesting message.
* `NOT_FOUND` indicates that the requested key was not found in the Kinetic Device's data store. Passing `force: true` in the `KeyValue` object on a `DELETE` operation ignores the failure and completes the operation with SUCCESS.
* `VERSION_MISMATCH` indicates that the `PUT` or `DELETE` operation failed because the `dbVersion` passed in the `KeyValue` object does not match the store's version. Passing `force: true` in the `KeyValue` object ignores the mismatch and completes the operation.
* `NO_SPACE` indicates that the drive is full. There are background processes which may free space, so this error may occur once, and not on subsequent tries even though no data has been explicitly removed. Similarly, executing a delete may not immediately free space, so a `PUT` which fails with this error may not immediately succeed even after a `DELETE` which should free space.
* `NO_SUCH_HMAC_ALGORITHM` indicates that the `hmacAlgorithm` field in the `Security` message was invalid.
* `INVALID_REQUEST` indicates that the request is not valid. Subsequent attempts with the same request will return the same code. Example: PUT a key whose size exceeds the specified maxKeySize in limits.
* `NOT_ATTEMPTED` indicates that a P2P operation was received but was not even attempted due to some other error halting execution early.
* `REMOTE_CONNECTION_ERROR` indicates that a P2P operation was attempted but could not be completed.
* `NESTED_OPERATION_ERRORS` indicates that a P2P request completed but that an operation (possibly nested) failed.
* `EXPIRED` indicates that an operation did not complete in the allotted time.
* `DEVICE_LOCKED` indicates that the device is currently locked.
* `DEVICE_ALREADY_UNLOCKED` indicates that the device was already unlocked.
* `CONNECTION_TERMINATED` indicates that the connection is being terminated. Details as to why are set in the message string.
* `INVALID_BATCH` indicates that the batch request is not valid. Subsequent attempts with the same batch request will return the same code. Example: A batch that contains a command other than put or delete.
* `SERVICE_BUSY` indicates that there are too many requests in the device at this time. The common response is to wait and retry the operation with an exponential back-off.
* `DATA_ERROR` indicates that a data error happened and either `earlyExit` was set to True or the timeout specified in the `timeout` field happened.
* `PERM_DATA_ERROR` indicates that a data error happened and all possible error recovery operations have been performed. There is no value to trying this again.
      
Error codes defined in the protocol file but not currently used:

* `HEADER_REQUIRED`

It is possible that an error will occur that may prevent the Kinetic Device from returning a `protobuf` message with a status code before closing the connection (network communication failures).

## No Op
The `NOOP` operation can be used as a quick test of whether the Kinetic Device is running and available. If the Kinetic Device is running, this operation will always return SUCCESS.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be NOOP
    messageType: NOOP
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    
    // messageType should be NOOP_RESPONSE
    messageType: NOOP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```


## Modify Value Operations

### Cross-Cutting Concerns

Within the `body` message of a value modification operation, many fields in the `keyValue` apply to all operations.

```
command: {
...
	body: {
		keyValue {
      		// The key for the value being set
    	  	key: "..."

	      	// Versions are set on objects to support optimistic locking.
      		// For operations that modify data, if the dbVersion sent in the 
      		// request message does not match the version stored in the db, the
      		// request will fail.
	      	dbVersion: "..."

      		// Specifies what the next version of the data will be if this 
      		// operation is successful.
	      	newVersion: "..."

      		// If set to True, puts will ignore any existing version (if it exists), 
          // and deletes will ignore any existing version or if the key is not 
          // found (allowing a success on the delete of a non-existent key).
      		force: true

	      	// The integrity value for the data. This value should be computed
      		// by the client application by applying the hash algorithm 
      		// specified below to the value (and only to the value). 
      		// The algorithm used should be specified in the algorithm field. 
      		// The Kinetic Device will not do any processing on this value.
      		tag: "..."

      		// The algorithm used by the client to compute the tag.
 		    // The allowed values are: SHA1, SHA2, SHA3, CRC32, CRC64
      		algorithm: ...

      		// Allows client to specify if the data must be written to disk 
      		// immediately, or can be written in the future.
      		//
      		// WRITETHROUGH:  This request is made persistent before returning.
      		//                This does not effect any other pending operations.
      		// WRITEBACK:     They can be made persistent when the drive chooses,
      		//        	  or when a subsequent FLUSH is give to the drive.
      		// FLUSH: 	  All pending information that has not been written is 
      		//		  pushed to the disk and the command that specifies 
      		// 		  FLUSH is written last and then returned. All WRITEBACK writes
      		//		  that have received ending status will be guaranteed to be
      		//		  written before the FLUSH operation is returned completed.
      		synchronization: ...
    }
  }
}
```

### PUT
The `PUT` operation sets the value and metadata for a given key. If a value already exists in the store for the given key, the client must pass a value for `dbVersion` which matches the stored version for this key to overwrite the value metadata. This behavior can be overridden (so that the version is ignored and the value and metadata are always written) by setting `forced` to `true` in the `KeyValue` option.

**Request Message**

The following request will add a key value pair to the store.

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // The messageType should be PUT
    messageType: PUT
  }
  body {
    keyValue {
      // See write operation cross cutting concerns
      newVersion: "..."
      key: "..."
      dbVersion: "..."
      tag: "..."
      algorithm: ...
      synchronization: ...
    }
  }
}
```

**Response Message**
When the key is successfully written, the device will respond with the following message:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be PUT_RESPONSE
    messageType: PUT_RESPONSE
  }
  body {
    keyValue {
    	// Empty
    }
  }
  status {
    // A successful PUT will return SUCCESS
    code: SUCCESS
  }
}
```

Error Cases:

* `code = VERSION_MISMATCH`
	* For a PUT of a new key (insert, not update) specifying a dbVersion
	*  If the version doesn't match (should not occur for create)
* `code = NOT_AUTHORIZED`
	* If the identity doesn't have permission to put this value
* `code = INVALID_REQUEST`
	* If the length of the key or value exceeds the device limits


### Delete
The `DELETE` operation removes the entry for a given key. It respects the same locking behavior around `dbVersion` and `force` as described in the previous sections.

**Request Message**

The following request will remove a key value pair to the store.

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be DELETE
    messageType: DELETE
  }
  body {
    keyValue {
      key: "..."
	  // See write operation cross cutting concerns
      synchronization: ...
    }
  }
}
```

**Response Message**
When the entry is successfully removed, the device will respond with the following message:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    
    // messageType should be DELETE_RESPONSE
    messageType: DELETE_RESPONSE
  }
  body {
    keyValue {
    }
  }
  status {
  // A successful DELETE will return SUCCESS
    code: SUCCESS
  }
}
```

There are many cases where a delete could fail with a properly functioning drive. The following `status.code` values identify these cases:

* `code = VERSION_MISMATCH` The dbVersion in the request doesn't match the version stored in the device.
* `code = NOT_FOUND` The key was not found in the data store.
* `code = NOT_AUTHORIZED` The identity doesn't have permission to delete this value.


### Flush
The `FLUSHALLDATA` operation flushes any outstanding PUTs or DELETEs on the device. For example, if the client `PUT` many keys with `synchronization=WRITEBACK` the data
would not be guaranteed to be persisted, so power cycling could result in lost data. When a `FLUSHALLDATA` command returns, all previous operations with `synchronization=WRITEBACK` on
this connection are guaranteed to be persisted. Data on separate connections is not guaranteed to be persisted, but may as an indirect consequence of this operation.

**Request Message**

The following request will flush the write cache.

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be FLUSHALLDATA
    messageType: FLUSHALLDATA
  }
  body {
  }
}
```

**Response Message**
When the cache is flushed, the device will return the following message:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...

    // messageType should be FLUSHALLDATA_RESPONSE
    messageType: FLUSHALLDATA_RESPONSE
  }
  body {
  }
  status {
  // A successful FLUSHALLDATA will return SUCCESS
    code: SUCCESS
  }
}
```


## Read Operations
There are a number of operations which are designed to allow clients to read values from the Kinetic Device. They will be discussed in this section.

### Cross-Cutting Concerns

Within the `body` message of a read value operation, many fields in the `keyValue` message apply to all operations.


```
keyValue {
      // The key identifying the value in the data store.
      key: "..."

      // If true, only metadata (not the full value) will be returned
      // If false, metadata and value will be returned
	  metadataOnly: ...    
}
```


### GET
The `GET` operation is used to retrieve the value and metadata for a given key. 

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    
    // The mesageType should be GET
    messageType: GET
  }
  body {
    keyValue {
      // See above
      key: "..."
    }
  }
}
```

**Response Message**

A successful response will return the value in the top level Kinetic PDU, and will have a `SUCCESS` status:

```   
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    conectionID: ...
    ackSequence: ...
    // messageType should be GET_RESPONSE
    messageType: GET_RESPONSE
  }
  body {
    keyValue {
      // These fields are documented above
      key: "..."
      dbVersion: "..."
      tag: ""
      algorithm: SHA2
    }
  }
  status {
    code: SUCCESS
  }
}
```

There are many cases where a read could fail with a properly functioning drive. The following `status.code` values identify these cases:

* `NOT_FOUND` The key does not exist in the data store (the Kinetic PDU will have a zero-length value component).
* `NOT_AUTHORIZED` The identity doesn't have permission to put this value.


### Get Version
The `GETVERSION` operation provides the current store version for a given key.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETVERSION
    messageType: GETVERSION
  }
  body {
    keyValue {
      // See above.
      key: "..."
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // messageType should be GETVERSION_RESPONSE
    messageType: GETVERSION_RESPONSE
  }
  body {
    keyValue {
      // The dbVersion is the only entry in the keyValue object that will
      // be returned by the server
      dbVersion: "..."
    }
  }
  status {
    code: SUCCESS
  }
}
```
Error Cases:

* `code = NOT_FOUND` The key does not exist in the data store (the Kinetic PDU will have a zero-length value component).
* `code = NOT_AUTHORIZED` The requester doesn't have permission to put this value.



### Get Next
The `GETNEXT` operation takes a key and returns the value for the next key in the sorted set of keys. Keys are sorted lexicographically by their byte representation.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETNEXT
    messageType: GETNEXT
  }
  body {
    keyValue {
      // Note that this is different from GET in that you 
      // will not get the value for this key, but the value for the subsequent 
      // key in the ordering.
      key: "..."
    }
  }
}
```

**Response Message**

A successful response will return the value in the top level Kinetic PDU, and will have a `SUCCESS` status:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // messageType should be GETNEXT_RESPONSE
    messageType: GETNEXT_RESPONSE
  }
  body {
    keyValue {
      // This is the key for the value that is being returned
      // This will be different from the key passed in the request
      key: "..."
      dbVersion: "..."
      tag: ""
      algorithm: SHA2
    }
  }
  status {
	// If the operation does not succeed, a different code will be specified. 
	// See below.
    code: SUCCESS
  }
}
```

Error Cases:

* `code = NOT_FOUND`
	* This can occur if the given key is the last key in the store, or if the key given is not included in the store but would be sorted after the last key.
	
Edge Cases:

 * If a `key` is provided which is not found in the store, the service will find the first key which would be sorted after the given key. For example, if the store has keys `key0` and `key2` and the client sends a request for `GETNEXT` of `key1`, the device will return the value for `key2`.

### Get Previous
The `GETPREVIOUS` operation takes a key and returns the value for the previous key in the sorted set of keys. Keys are sorted lexicographically by their byte representation.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETPREVIOUS
    messageType: GETPREVIOUS
  }
  body {
    keyValue {
      // Note that this is different from GET in that you 
      // will not get the value for this key, but the value for the preceding
      // key in the ordering.
      
      key: "..."
    }
  }
}
```

**Response Message**

A successful response will return the value in the top level Kinetic PDU, and will have a `SUCCESS` status:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // messageType should be GETPREVIOUS_RESPONSE
    messageType: GETPREVIOUS_RESPONSE
  }
  body {
    keyValue {
      // This is the key for the value that is being returned
      // This will be different from the key passed in the request
      key: "..."
      
      // These fields are documented above
      dbVersion: "..."
      tag: "..."
      algorithm: ...
    }
  }
  status {
	// If the operation does not succeed, a different code will be specified. 
	// See below.
    code: SUCCESS
  }
}
```

Error Cases:

* `code = NOT_FOUND`
	* This can occur if the given key is the first key in the store, or if the key given is not included in the store but would be sorted before the first key.
	
Edge Cases:

 * If a `key` is provided which is not found in the store, the service will find the first key which would be sorted before the given key. For example, if the store has keys `key0` and `key2` and the client sends a request for `GETPREVIOUS` of `key1`, the device will return the value for `key0`.



### Get Key Range
The `GETKEYRANGE` operation takes a start and end key and returns all keys between those in the sorted set of keys. This operation can be configured so that the range is either inclusive or exclusive of the start and end keys, the range can be reversed, and the requester can cap the number of keys returned.

Note that this operation does not fetch associated values, or other metadata. It only returns the keys themselves, which can be used for other operations.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    
    // messageType should be GETKEYRANGE
    messageType: GETKEYRANGE
  }
  body {
  	// The range message must be populated
    range {
      // The beginning of the requested range
      startKey: "..."
      
      // True indicates that the start key should be included in the returned 
      // range
      startKeyInclusive: ...
      
      // The end of the requested range
      endKey: "..."

      // True indicates that the end key should be included in the returned 
      // range
      endKeyInclusive: ...
      
      // The maximum number of keys returned, in sorted order
      maxReturned: ...
      
      // If true, the key range will be returned in reverse order, starting at
      // endKey and moving back to startKey.  For instance
	  // if the search is startKey="j", endKey="k", maxReturned=2,
	  // reverse=true and the keys "k0", "k1", "k2" exist
	  // the system will return "k2" and "k1" in that order.
      reverse: ....
    }
  }
}
```

**Response Message**


```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    messageType: GETKEYRANGE_RESPONSE
  }
  body {
  	// The range message is populated with up to maxReturned keys. 
  	// If no keys are found in the range then the range message will be omitted 
  	// and the status code will be SUCCESS
    range {
      key: "..."
      key: "..."
	  ...
      key: "..."
    }
  }
  status {
    code: SUCCESS
  }
}

```


Error Cases:

* `code = INVALID_REQUEST`
    * The `maxReturned` exceeded the limit.

Edge Cases:

* If neither `startKey` or `endKey` are found in the store, any keys that would be sorted between them will be returned.
* If the given keys are out of order (e.g. `startKey` is sorted after `endKey`), then no keys will be returned.

**Permissions**

This operation should only return keys for which the requesting identity has the `RANGE` permission on an applicable scope. For instance, consider a store that contains `k0`, `k1`, `k2`, `k3`, and `k4`, where the requesting identity does not have `RANGE` permission on any scope which applies to `k2`. Then if that identity requests a `GETKEYRANGE` with `startKey=k0` (inclusive), `endKey=k4` (inclusive), maxReturned=5 the Kinetic Device will return `k0`, `k1`, 'k3', and 'k4'.


## Setup
The `SETUP` operation can be used to set the device's `clusterVersion`, or to download new firmware on the device. As these operations are quite different, we'll discuss them separately in this section. The Kinetic Device will only allow one of these operations per message.


### Set Cluster Version

**Request Message**

``` 
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // Important: this should be the current cluster version. This operation is
    // intended to change the clusterVersion, but the current clusterVersion 
    // must be specified here.
    clusterVersion: ...
    
	// See top level cross cutting concerns for header details
    connectionID: ...
    sequence: ...
    
	// The messageType should be SETUP
    messageType: SETUP
  }
  body {
    setup {
      // This is the clusterVersion being set on the device.
      newClusterVersion: 1
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be SETUP_RESPONSE
    messageType: SETUP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

### Firmware Download
This operation should be used load new firmware on the device.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be SETUP
    messageType: SETUP
  }
  body {
    setup {
      // Indicates that the value (in the Kinetic PDU) will contain the firmware
      firmwareDownload: true
    }
  }
}
```

The value field in the Kinetic PDU (describe above) will contain the firmware payload.

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be SETUP_RESPONSE
    messageType: SETUP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

## Administration

### Set Pin
This operation should be used to set your lock pin or erase pin. The example below is for lock pin.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be SECURITY
    messageType: SECURITY
  }
  body {
    security {
      // The current lock pin for the device
      oldLockPIN: "..."
      // What you want the new lock pin to be
      newLockPIN: "..."
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be SECURITY_RESPONSE
    messageType: SECURITY_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

### Lock and Unlock
This operation should be used to lock or unlock a device. The example below is to lock a device.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: pinAUTH
  PINauth {
    pin: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be PINOP
    messageType: PINOP
  }
  body {
    pinOperation {
      // Specify the intention of the command with the enumeration value LOCK_PINOP
      PinOpType: LOCK_PINOP
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: pinAUTH
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be PINOP_RESPONSE
    messageType: PINOP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

### Instant Secure Erase
This operation should be used to erase all stored data from the device. 

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: pinAUTH
  PINauth {
    pin: "..."
  }
  commandBytes: "..."
}
// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be PINOP
    messageType: PINOP
  }
  body {
    pinOperation {
      // Specify the intention of the command with the enumeration value SECURE_ERASE_PINOP
      PinOpType: SECURE_ERASE_PINOP
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: pinAUTH
  commandBytes: "..."
}
// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be PINOP_RESPONSE
    messageType: PINOP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

### ACL Setup

Some semantics of the ACL operation are noteworthy:

* A `identity` has one ACL, and an ACL only applies to one `identity`. They have a one-to-one relationship.
* An ACL list cannot be updated, only set. Each request to SECURITY with a well-formed security body will overwrite the existing setup.
* To make a Security operation (set ACLs) the requesting identity must have an applicable scope with a SECURITY permission.


To set the ACL for a identity (or many identities), a request like the following could be sent. See the Access Control section above for further explanation of the ACL message.

**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    
    // messageType should be SECURITY
    messageType: SECURITY
  }
  body {
    // The security message must be present.
    security {
      acl {
        // The identity this ACL applies to
        identity: 1
        // The identity's HMAC key, a shared secret
        key: "...."
        // The algorithm used to compute the HMAC for 
        // this identity
        hmacAlgorithm: ...
        
        // The scope message has at least one permission, in this example there
        // are many
        scope {
          permission: READ
          permission: WRITE
          permission: DELETE
          permission: RANGE
          permission: SETUP
          permission: P2POP
          permission: GETLOG
          permission: SECURITY
        }
      }
      
      // This ACL shows that multiple scopes can be set for a identity in one
      // ACL message
      acl {
        identity: 2
        key: "..."
        hmacAlgorithm: ...

        // This simple scope allows identity 2 to read all keys
        scope {
          permission: READ
        }
        
        // This scope gives identity 2 the ability to write keys if and only if
        // "test" is a substring of key starting at offset 3. For example, with 
        // this scope identity 2 could PUT keys: "xyztest1", "001test2", etc
        // but could not put keys: "somethingElse", "test123", "1234test"
        scope {
          offset: 3
          value: "test"
          permission: WRITE
        }
      }
      
      // More ACLs for additional identities may be specified in the
      // same security message...
      acl {
        identity: 3
        key: "..."
        hmacAlgorithm: ...
        scope {
          permission: WRITE
        }
      }
      acl {
        identity: 4
        key: "..."
        hmacAlgorithm: ...
        scope {
          permission: DELETE
        }
      }
   }
}
```


**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    
    // messageType should be SECURITY_RESPONSE
    messageType: SECURITY_RESPONSE
  }
  status {
  	// If successful, code will be SUCCESS
    code: SUCCESS
  }
}
```

Error Cases:

* `code=NOT_AUTHORIZED` if the requesting identity does not have the `SECURITY` permission for an applicable scope.
* `code=INVALID_REQUEST` if there is something malformed about the request all parts of the command will fail. Some examples are listed below. 
	* if there are no permissions provided in a scope
	* if one of the permissions provided is invalid (e.g. Permission.INVALID)
  * if offset is greater than the max key size


### Get Log

The `GETLOG` operation gives the client access to log information. The request message must include at least one type and can have many types. The supported types are:

* `UTILIZATIONS`
* `TEMPERATURES`
* `CAPACITIES`
* `CONFIGURATION`
* `STATISTICS`
* `MESSAGES`
* `LIMITS`

Below we will show the message structure used to request all types in a single `GETLOG` request.


**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // The messageType should be GETLOG
    messageType: GETLOG
  }
  body {
    // The body should contain a getLog message, which must have
    // at least one value for type. Multiple are allowed. 
    // Here all types are requested.
    getLog {
      type: CAPACITIES
      type: CONFIGURATION
      type: MESSAGES
      type: STATISTICS
      type: TEMPERATURES
      type: UTILIZATIONS
    }
  }
}
```

**Respose Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // messageType should be GETLOG_RESPONSE
    messageType: GETLOG_RESPONSE
  }
  body {
    getLog {
      // Each type requested is provided in the response
      type: CAPACITIES
      type: CONFIGURATION
      type: MESSAGES
      type: STATISTICS
      type: TEMPERATURES
      type: UTILIZATIONS
      type: LIMITS
      
      // Many utilization messages may be returned
      utilization {
      	// The name of the resource being reported       
      	// For example: HDA, ENO, CPU...
        name: "..."
        // The value for this resource's utilization.
        // Value will be between 0.00 and 1.00.
        value: 0.2
      }
      
      utilization {
        name: "...""
        value: ...
      }
      ...
      
      // Many temperature messages may be returned
      temperature {
      	// The name of the resource being reported
        name: "..."

		// The current temperature in degrees celsius
        current: 39.0
		// The current temperature in degrees celsius
        minimum: 5.0
        // The current temperature in degrees celsius
        maximum: 100.0
		// The current temperature in degrees celsius        
        target: 25.0
      }
	
	  // Only one configuration message will be included      
      configuration {
        // The vendor of the Kinetic Device. 
        vendor: "..."

        // The model of the Kinetic Device
        model: "..."

        // The serial number of the Kinetic Device
        serialNumber: "..."

        // The version of the kinetic software running on the device
        version: "..."

        // Multiple interface messages will appear, one per network interface
        // that the Kinetic Device.
        interface {
          name: "..."
          MAC: "..."
          ipv4Address: "..."
          ipv6Address: "..."
        }
        interface {
          name: "..."
          ipv4Address: "..."
          ipv6Address: "..."
        }
        // The port where the kinetic service is running
        port: ...
        // The port where the kinetic service is running over SSL
        tlsPort: ...
        // The date this version of the kinetic service was compiled
        compilationDate: "..."
        // A checksum of the source code
        sourceHash: "..."
      }
      
      // There should be one statistics message per messageType (GET, PUT, etc)
      // The statistics messages aggregate statistics for each messageType.
      statistics {
        // Which messageType these statistics apply to
        messageType: PUT
        // How many times this messageType has been received
        count: ...
        // The sum length of all the value portion of the 
        // Kinetic PDU messages sent since starting the Kinetic Device
        bytes: ...
      }
      ...
      statistics {
        messageType: GET
        count: ...
        bytes: ...
      }
      
      // Only one capacity message will be included
      capacity {
        nominalCapacityInBytes: ...
      	portionFull: ...
      }
      
      // bytes representing recent Kinetic Device log messages
      messages: "..."
      
      // limits that the device will enforce
      limits {
        maxKeySize = ...
        maxValueSize = ...
        maxVersionSize = ...
        maxTagSize = ...
        maxConnections = ...
        maxOutstandingReadRequests = ...
        maxOutstandingWriteRequests = ...
        maxMessageSize = ...
        maxKeyRangeCount = ...
      }
    }
  }
  status {
    code: SUCCESS
  }
}
```


## Peer to Peer
The `PEER2PEERPUSH` operation allows a client to instruct a Kinetic Device to copy a set of keys (and associated value and metadata) to another Kinetic Device. Peer To Peer operations can be nested, so a client could tell device A to copy certain keys to device B, and then have device B copy a set of keys to device C, and so on. 


**Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    messageType: PEER2PEERPUSH
  }
  body {
    p2pOperation {
      peer {
      	// The network address of the peer
        hostname: "..."
        // The port on which the peer is running the Kinetic service
        port: ...
        tls: ...
      }
      operation {
      	// The key to copy from the source peer.
        key: ""

		version: "..."
		
		// If true, force write ignoring version
		force: ...
		
  		// The key to use in the destination peer.
		newKey: "..."
		
		// This is a nested Peer To Peer Push operation. The recursive structure
		// allows arbitrarily deep (up to the message size cap) nesting of
		// p2p operations.
        p2pop {
          // Like the top-level p2pOperation, this specifies a peer and
          // a set of operations
          peer {
            hostname: "..."
            port: ...
            tls: false
          }
          operation {
            key: "..."
          }
          // Multiple operations can be specified in one P2POperation
          operation {
            key: "..."
          }

        }
      }
    }
  }
}
```

**Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    messageType: PEER2PEERPUSH_RESPONSE
  }
  body {
    p2pOperation {
      // See below for a description of error handling
      allChildOperationsSucceeded: false,
      operation {
        key: "..."
        newKey: "..."
        force: ...
        status {
          code: SUCCESS
        }
        p2pop {
          peer {
            hostname: "..."
            port: ...
            tls: false
          }
          // See below for a description of error handling
          allChildOperationsSucceeded: false,
          operation {
            key: "..."
			status {
				// Status messages can be nested. This is what it would be 
				// returned if an operation failed because the key was not found
         	 	code: NOT_FOUND
	     	}           
          }
          operation: {
          	key: "...",
          	status {
          		code: NESTED_OPERATION_ERRORS
          	}
          }
        }
      }
    }
  }
  status {
    code: SUCCESS
  }
}
```

Error Cases:

If the command does not start or is terminated early, the status will be reflect that error.

If the request completed but some operations encountered errors, the code will be `NESTED_OPERATION_ERRORS`.

If all operations and nested P2P Operations within the top-level operation are successful, the `Status.code` in the `Command` message will be `SUCCESS`.

For each P2POperation, if any of its nested operations fail, then it will have the flag `allChildOperationsSucceeded` set to false. Otherwise, that flag will be set to true.

Any operation may fail for the same reason any `PUT` could fail. Operations have their own `Status` message to report these failures.
In addition to the failures observed by `PUT`, Operations may experience:

* `NOT_ATTEMPTED` The top level request was aborted before this operation could be attempted, either due to timeouts or another error (e.g. an IO error).
* `REMOTE_CONNECTION_ERROR` The operation was attempted, but an error prevented the operation from completing.

## Batch Operation

Batch Operation allows a group of K/V commands (PUT and DELETE) to perform all at once.  The commands within a batch are committed to the persistent store if all commands can be committed or otherwise nothing is committed.  

A batch operation is started with a START_BATCH command and ended with a END_BATCH command.  The supported operations are PUT and DELETE commands within a batch.

START_BATCH and END_BATCH have the request-response style messaging pattern similar to most of the Kinetic commands, such as GET command.  

All (PUT/DELETE) operations within a batch do not have response messages.  

The following Batch message construct is included in the END_BATCH and END_BATCH_RESPONSE messages.

```
// This is included in the END_BATCH and END_BATCH_RESPONSE.
message Batch {
  // set by the client library in END_BATCH request message.
  // the total number of operations in the batch
  optional uint32 count = 1;

  // set by the drive in END_BATCH_RESPONSE message.
  // If a batch is committed successfully, all sequence Ids of those
  // commands (PUT/DELETE) performed in the batch are
  // added in the END_BATCH_RESPONSE message.
  repeated uint64 sequence = 2 [packed=true];

  // This field is set by the drive if a batch commit failed.
  // The sequence of the first operation to fail in the batch.
	// There is no guarantee that the previous sequences would have succeeded.
  optional uint64 failedSequence = 3;
}  

```

**START_BATCH Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    // The messageType should be START_BATCH
    messageType: START_BATCH
    batchID: ...
  }
  body {
  }
}
```

**START_BATCH Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    // The messageType should be START_BATCH_RESPONSE
    messageType: START_BATCH_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
```

**END_BATCH Request Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    connectionID: ...
    sequence: ...
    messageType: END_BATCH
    batchID: ...
  }
  body {
    batch {
      count: 2
    }  
  }
}
```

**END_BATCH Response Message**

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    ackSequence: ...
    messageType: END_BATCH_RESPONSE
  }
  body {
    batch {
      // see above description in message Batch construct
      sequence: ...
      sequence: ...
    }
  }
  status {
    code: SUCCESS
   }
}
```

Error Cases:

If an error is detected before received the END_BATCH command, such as exceeding the max number of deletes within a batch, the device sends an Unsolicited Status Message with StatusCode INVALID_BATCH and closed the connection.

If a batch command (ie, PUT, DELETE) is received but there is no associated START BATCH, the device sends an Unsolicited Status Message with StatusCode INVALID_BATCH and closes the connection.

Example:

```
message {
  // See above for descriptions of these fields
  authType: UNSOLICITED
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
  }
  status {
    code: INVALID_BATCH
  }
}
```

If an error is detected after received the END_BATCH command, such as encountered a version mismatch for a PUT command, the device sends a END_BATCH_RESPONSE message with status code set to the failure cause (VERSION_MISMATCH in this example).  The failed sequence number of the command that caused the failure is set in the failedSequence field of the END_BATCH_RESPONSE message.

Example:

```
message {
  // See above for descriptions of these fields
  authType: HMACAUTH
  hmacAuth {
    identity: ...
    hmac: "..."
  }
  commandBytes: "..."
}

// human readable commandBytes (decoded from commandBytes) 
command {
  header {
    // See above for descriptions of these fields
    connectionID: ...
    // The sequence of the end batch message
    ackSequence: ...
    messageType: END_BATCH_RESPONSE
  }
  body {
    batch {
      // The sequence of the failed put
      failedSequence: ...
    }
  }
  status {
    code: VERSION_MISMATCH
  }
}
```

If the device is LOCKed before an END BATCH is received, the device returns an Unsolicited Status Message and the uncommitted batch is removed.  If an END BATCH is received and the batch has started processing before LOCK request is received, the batch is processed before the device is LOCKed.

If an ISE command is received before an END BATCH is received, the device sends an Unsolicited Status Message and closes the connection. The uncommitted batch is removed.
