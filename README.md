# Overview
Kinetic is a key-value storage system. A Kinetic Device (e.g. a Kinetic Drive or a traditional server running the Java Reference Implementation) stores key-value objects. Kinetic Client applications can communicate with a Kinetic Device by sending messages over a network using TCP. Each individual message is called a “Kinetic Protocol Data Unit” (Kinetic PDU) and represents an individual request or response. For example, a Kinetic Client may send a message requesting the value associated with a particular key to a Kinetic Device. The device would respond with a message containing the value. 

## Document Assumptions
This document describes the structure of Protocol Buffer messages in detail. It is important to have a familiarity with the Protocol Buffer data interchange format ([https://code.google.com/p/protobuf/](https://code.google.com/p/protobuf/)). Where data types are specified with respect to fields in `protobuf` messages, the Scalar Value Types documented here: [https://developers.google.com/protocol-buffers/docs/proto](https://developers.google.com/protocol-buffers/docs/proto) will be used.

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

- A single command
- An HMAC of the byte representation of the command

Each command contains a:

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
		// with the ACL. Scopess can further restrict which situations
		// those permissions apply to by using the offset, value,
		// and TlsRequired fields
		message Scope {
			// Offset and value are optional and should be used to restrict 
			// which keys the Scope applies to. If offset and value are
			// specified, the permission will only apply to keys that match
			// the value at the given offset. This is analogous to a substring
			// match in many languages, where the key in question is the target.
			optional int64 offset = 1;
			optional bytes value = 2;
			
			// The Permission being granted.
			// There can be many, there must be at least one.
			repeated Permission permission = 3;
			
			// Optional boolean, defaults to false.
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
           // this is the default
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
command {
  header {
  	// Optional int64, default value is 0
    // The version number of this cluster definition. If this is not equal to 
    // the value on the device, the request is rejected and will return a 
    // `VERSION_FAILURE` `statusCode` in the `Status` message.
    clusterVersion: ...

    // Required int64
    // The identity associated with this request. See the ACL discussion above.
    // The Kinetic Device will use this identity value to lookup the
    // HMAC key (shared secret) to verify the HMAC.
    identity: ...

	// Required int64
    // A unique number for this connection between the source and target. 
    // On the first request to the drive, this should be the time of day in 
    // seconds since 1970. The drive can change this number and the client must
    // continue to use the new number and the number must remain constant 
    // during the session
    connectionID: ...

	// Required int64
	// Sequence is a monotonically increasing number for each request in a TCP 
	// connection. 
    sequence: ...

	// Required MessageType
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

// Required bytes
// The HMAC of this message used to verify integrity. 
// The HMAC is taken of the byte-representaiton of the command message of this 
// protobuf message. An identity-specific shared secret is used to compute the HMAC.
// The Kinetic Device must have the key associated with the identity in
// the header.
// For example, in pseudocode where a computeHMAC function exists which takes 
// a value and an algorithm:
//	 hmac = computeHMAC(message.command.toBytes(), identityHMACAlgorithm)
hmac: "..."
```

**Response Message**

```
command {
  header {
  	// Required int64.
    // In a response message, ackSequence will be the same as the 
    // sequence value set in the request message.
    // The client can use this to map async responses to their
    // associated requests. 
    // This is important because operations within a connection may be reorderd.
    ackSequence: ...
    
    // In a response, messageType corresponds to the requested messageType.
    // For instance, requests with a PUT messageType will receive a response 
    // with a PUT_REPONSE messageType.
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
// Required bytes
// See the description for the request above. Responses will include an HMAC 
// in addition to request, using the identity-specific key.
hmac: ""

```

###Error Cases###
When an error occurs on the Kinetic Device, the response message includes a `status` with a `code`. These codes are enumerated in the `StatusCode` enum in the protocol definition. They will be discussed here in more detail.

* `INTERNAL_ERROR` indicates that the Kinetic Device experiences a malfunction. (Currently this code is returned in certain cases that don't indicate a drive malfunction, these will be updated.) 
* `HMAC_FAILURE` indicates that the HMAC of the request is incorrect or missing. This will also be returned when an unknown identity is set in the header, since the device cannot verify an HMAC for an unknown identity.
* `NOT_AUTHORIZED` indicates the attemped operation could not be completed because the identity set in the header did not have authorization. This may mean that the identity does not have the required Permission in any Scope in the ACL, or it may indicate that the Scope containing that Permission does not apply (due to offset & index or tls rules).
* `VERSION_FAILURE` indicates that the `clusterVersion` of the Kinetic Device does not match the `clusterVersion` set in the header of the requesting message.
* `NOT_FOUND` indicates that the requested key was not found in the Kinetic Device's data store. 
* `VERSION_MISMATCH` indicates that the `PUT` or `DELETE` operation failed because the `dbVersion` passed in the `KeyValue` object does not match the store's version. Pasing `force: true` in the `KeyValue` object ignores the mismatch and completes the operation.
* `NO_SPACE` indicates that the drive is full. There are background processes which may free space, so this error may occur once, and not on subsequent tries even though no data has been explicitly removed. Similarly, executing a delete may not immediately free space, so a `PUT` which fails with this error may not immediately succeed even after a `DELETE` which should free space.
* `NO_SUCH_HMAC_ALGORITHM` indicates that the `hmacAlgorithm` field in the `Security` message was invalid.
* `INVALID_REQUEST` indicates that the request is not valid. Subsequent attempts with the same request will return the same code. Examples: GET does not specify keyValue message, GETKEYRANGE operation does not specify startKey, etc.
* `NOT_ATTEMPTED` indicates that a P2P operation was received but was not even attempted due to some other error halting execution early.
* `REMOTE_CONNECTION_ERROR` indicates that a P2P operation was attempted but could not be completed.
* `NESTED_OPERATION_ERRORS` indicates that a P2P request completed but that an operation (possibly nested) failed.
* `EXPIRED` indicates that an operation did not complete in the alotted time.


A number of error codes are defined in the protocol file but not currently used:

* `HEADER_REQUIRED`
* `SERVICE_BUSY`
* `DATA_ERROR`
* `PERM_DATA_ERROR`

It is possible that an error will occur that will prevent the Kinetic Device from returning a `protobuf` message with a status code. These are some situations:

* **Invalid Kinetic PDU:** If the Kinetic PDU is not formed as described above, the TCP connection will be closed abruptly. This includes the case that a value or protobuf message exceeds the size limitations.
* **Invalid Protobuf:** If the `protobuf` message cannot be decoded because it is not well formed, the TCP connection will be closed abruptly.


## No Op
The `NOOP` operation can be used as a quick test of whether the Kinetic Device is running and available. If the Kinetic Device is running, this operation will always return succeed.

**Request Message**

```
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    // messageType should be NOOP
    messageType: NOOP
  }
}
hmac: "..."
```

**Response Message**

```

command {
  header {
    // See above
    ackSequence: ...
    
    // messageType should be NOOP_RESPONSE
    messageType: NOOP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
hmac: ""
```


## Modify Value Operations

### Cross-Cutting Concerns

Within the `body` message of a value modification operation, many fields in the `keyValue` apply to all operations.

```
command: {
...
	body: {
		keyValue {
			// Required bytes
      		// The key for the value being set
    	  	key: "..."

			// Required bytes
	      	// Versions are set on objects to support optimistic locking.
      		// For operations that modify data, if the dbVersion sent in the 
      		// request message does not match the version stored in the db, the
      		// request will fail.
	      	dbVersion: "..."

			// Required bytes
      		// Specifies what the next version of the data will be if this 
      		// operation is successful.
	      	newVersion: "..."

			// Optional bool, default false
      		// Setting force to true ignores potential version mismatches
      		// and carries out the operation.
      		force: true

			// Optional bytes
	      	// The integrity value for the data. This value should be computed
      		// by the client application by applying the hash algorithm 
      		// specified below to the value (and only to the value). 
      		// The algorithm used should be specified in the algorithm field. 
      		// The Kinetic Device will not do any processing on this value.
      		tag: "..."

      		// The algorithm used by the client to compute the tag.
 		    // The allowed values are: SHA1, SHA2, SHA3, CRC32, CRC64
      		algorithm: ...

		// Optional Synchronization enum value, defaults to WRITETHROUGH
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

The following request will add a key value pair to the store. Note that `dbVersion` is not specified, this is allowed when adding (as opposed to updating) a value.

```
command {
  // See top level cross cutting concerns for header details
  header {
    clusterVersion: ...
    identity: ...
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
      tag: "..."
      algorithm: ...
      synchronization: ...
    }
  }
}
// See above
hmac: "..."
```

**Response Message**
When the key is successfully written, the device will respond with the following message:

```
command {
  header {
  	// See above
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
hmac: ""
```

Error Cases:

* `code = VERSION_MISMATCH`
	* For a PUT of a new key (insert, not update) specifying a dbVersion
	*  If the version doesn't match (should not occur for create)
* `code = NOT_AUTHORIZED`
	* If the identity doesn't have permission to put this value, in this case `status.statusMessage` will be "permission denied."
* The connection will be closed without reply if the value is too long. (The result in a client library may be some sort of IO Error, depending on implementation).


### Delete
The `DELETE` operation removes the entry for a given key. It respects the same locking behavior around `dbVersion` and `force` as described in the previous sections.

**Request Message**

The following request will remove a key value pair to the store.

```
command {
  // See top level cross cutting concerns for header details
  header {
    clusterVersion: ...
    identity: ...
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
// See above
hmac: "..."
```

**Response Message**
When the entry is successfully removed, the device will respond with the following message:

```

command {
  // See top level cross cutting concerns for header details
  header {
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
hmac: "..."

```

There are many cases where a delete could fail with a properly functioning drive. The following `status.code` values identify these cases:

* `code = VERSION_MISMATCH` The dbVersion in the request doesn't match the version stored in the device.
* `code = NOT_FOUND` The key was not found in the data store.
* `code = NOT_AUTHORIZED` The identity doesn't have permission to delete this value, in this case `status.statusMessage` will be "permission denied."


### Flush
The `FLUSHALLDATA` operation flushes any outstanding PUTs or DELETEs on the device. For example, if the client `PUT` many keys with `synchronization=WRITEBACK` the data
would not be guaranteed to be persisted, so power cycling could result in lost data. When a `FLUSHALLDATA` command returns, all previous operations with `synchronization=WRITEBACK` on
this connection are guaranteed to be persisted. Data on separate connections is not guaranteed to be persisted, but may as an indirect consequence of this operation.

**Request Message**

The following request will flush the write cache.

```
command {
  // See top level cross cutting concerns for header details
  header {
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    // messageType should be FLUSHALLDATA
    messageType: FLUSHALLDATA
  }
  body {
  }
}
// See above
hmac: "..."
```

**Response Message**
When the cache is flushed, the device will return the following message:

```

command {
  // See top level cross cutting concerns for header details
  header {
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
hmac: "..."

```

**Permissions**
No special permissions are required.


## Read Operations
There are a number of operations which are designed to allow clients to read values from the Kinetic Device. They will be discussed in this section.

### Cross-Cutting Concenrs

Within the `body` message of a read value operation, many fields in the `keyValue` message apply to all operations.


```
keyValue {
      // Required bytes.
      // The key identifying the value in the data store.
      key: "..."

      // Optional bool, defaults to false.
      // If true, only metadata (not the full value) will be returned
      // If false, metadata and value will be returned
	  metadataOnly: ...    
}
```


### GET
The `GET` operation is used to retrieve the value and metadata for a given key. 

**Request Message**

```
command {
  header {
  	// See above for descriptions of these fields
    clusterVersion: ...
    identity: ...
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
// See above
hmac: "..."
```

**Response Message**

A successful response will return the value in the top level Kinetic PDU, and will have a `SUCCESS` status:

 ```   
command {
  header {
  	// See above
    ackSequence: ...
    // messageType should be GET_RESPONSE
    messageType: GET_RESPONSE
  }
  body {
    keyValue {
      // These fields are documented above
      key: ""
      dbVersion: ""
      tag: ""
      algorithm: SHA2
    }
  }
  status {
    code: SUCCESS
  }
}
hmac: "..."
```

There are many cases where a read could fail with a properly functioning drive. The following `status.code` values identify these cases:

* `NOT_FOUND` The key does not exist in the data store (the Kinetic PDU will have a zero-length value component).
* `NOT_AUTHORIZED` The identity doesn't have permission to put this value, in this case `status.statusMessage` will be "permission denied."


### Get Version
The `GETVERSION` operation provdes the current store version for a given key.

**Request Message**

```
command {
  header {
    // These fields are documented above
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETVERSION
    messageType: GETVERSION
  }
  body {
    keyValue {
      // Required. See above.
      key: "..."
    }
  }
}
hmac: "..."
```

**Response Message**

```
command {
  header {
  	// This field is documented above
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
hmac: ""
```
Error Cases:

* `code = NOT_FOUND` The key does not exist in the data store (the Kinetic PDU will have a zero-length value component).
* `code = NOT_AUTHORIZED` The requester doesn't have permission to put this value, in this case `status.statusMessage` will be "permission denied."



### Get Next
The `GETNEXT` operation takes a key and returns the value for the next key in the sorted set of keys. Keys are sorted lexicographically by their byte representation.

**Request Message**

```
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETNEXT
    messageType: GETNEXT
  }
  body {
    keyValue {
      // A key is required. Note that this is different from GET in that you 
      // will not get the value for this key, but the value for the subsequent 
      // key in the ordering.
      key: "..."
    }
  }
}
// See above
hmac: "..."
```

**Response Message**

```
command {
  header {
    // See above for descriptions of this field
    ackSequence: ...
    // messageType should be GETNEXT_RESPONSE
    messageType: GETNEXT_RESPONSE
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
// See above
hmac: "..."
```

Error Cases:

* `code = NOT_FOUND`
	* There is no key in the store that is sorted after the given key. 
	* This can occur if the given key is the last key in the store, of if the key given is not included in the store but would be sorted after the last key.
* `code = NOT_AUTHORIZED` The identity does not have read permission on the key that would be returned.
	
Edge Cases:

 * If a `key` is provided which is not found in the store, the service will find the first key which would be sorted after the given key. For example, if the store has keys `key0` and `key2` and the client sends a request for `GETNEXT` of `key1`, the device will return the value for `key2`.
 * Note that if the identity does not have permission to read the key passed in the `GETNEXT` request, but they do have permission to read the key that would be returned, the request should succeed.

### Get Previous
The `GETPREVIOUS` operation takes a key and returns the value for the previous key in the sorted set of keys. Keys are sorted lexicographically by their byte representation.

**Request Message**

```
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    // messageType should be GETPREVIOUS
    messageType: GETPREVIOUS
  }
  body {
    keyValue {
      // A key is required. Note that this is different from GET in that you 
      // will not get the value for this key, but the value for the subsequent
      // key in the ordering.
      
      key: "..."
    }
  }
}
// See above
hmac: "..."
```

**Response Message**

```
command {
  header {
    // See above for descriptions of this field
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
// See above
hmac: "..."
```

Error Cases:

* `code = NOT_FOUND`
	* There is no key in the store that is sorted brefore the given key. 
	* This can occur if the given key is the first key in the store, of if the key given is not included in the store but would be sorted before the first key.
* `code = NOT_AUTHORIZED`:
	* If the identity does not have read permission on the key that would be returned.
	
Edge Cases:

 * If a `key` is provided which is not found in the store, the service will find the first key which would be sorted before the given key. For example, if the store has keys `key0` and `key2` and the client sends a request for `GETPREVIOUS` of `key1`, the device will return the value for `key0`.
 * Note that if the identity does not have permission to read the key passed in the `GETNEXT` request, but they do have permission to read the key that would be returned, the request should succeed.



### Get Key Range
The `GETKEYRANGE` operation takes a start and end key and returns all keys between those in the sorted set of keys. This operation can be configured so that the range is either inclusive or exclusive of the start and end keys, the range can be reversed, and the requester can cap the number of keys returned.

Note that this operation does not fetch associated values, or other metadata. It only returns the keys themselves, which can be used for other operations.

**Request Message**

```
command {
  header {
    // See above for descriptions of these fields
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    
    // messageType should be GETKEYRANGE
    messageType: GETKEYRANGE
  }
  body {
  	// The range message must be populated
    range {
      // Required bytes, the beginning of the requested range
      startKey: "..."
      
      // Optional bool, defaults to false
      // True indicates that the start key should be included in the returned 
      // range
      startKeyInclusive: ...
      
      // Required bytes, the end of the requested range
      endKey: "..."

      // Optional bool, defaults to false
      // True indicates that the end key should be included in the returned 
      // range
      endKeyInclusive: ...
      
      // Required int32, must be greater than 0
      // The maximum number of keys returned, in sorted order
      maxReturned: ...
      
      // Optional bool, defaults to false
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
command {
  header {
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
hmac: "..."
```


Error Cases:

* `code = INVALID_REQUEST`
    * The `maxReturned` exceeded the limit, the `status.statusMessage` will be `Key limit exceeded.`

Edge Cases:

* If neither `startKey` or `endKey` are found in the store, any keys that would be sorted between them will be returned.
* If the given keys are out of order (e.g. `startKey` is sorted after `endKey`), then no keys will be returned.

**Permissions**

This operation should return the first contiguous block of keys for which the requesting identity has the `RANGE` permission on an applicable scope. This means that not necessarily each key in the requested range for which the identity has this permission will be returned. For instance, consider a store that contains `k0`, `k1`, `k2`, `k4`, and `k5`, where the requesting identity has the `RANGE` permission  on scopes which aply to `k0`, `k1`, `k4`, and `k5` but notably does not have `RANGE` permission on any scope which applies to `k2`. Then if that identity requests a `GETKEYRANGE` with `startKey=k0` (inclusive), `endKey=k5` (inclusive) the Kinetic Device will return `k0` and `k1`. When it reaches `k2`, for which it does not have a `RANGE` permission, it will stop the operation.


## Setup
The `SETUP` operation can be used to set the device's `clusterVersion` and `pin`, to perform an "Instant Secure Erase", or to download new firmware on the device. As these operations are quite different, we'll discuss them separately in this section. The Kinetic Device will only allow one of these operations per message (though syntactically several could be combined).


### Set Cluster Version

**Request Message**

``` 
command {
  header {
    // Important: this should be the current cluster version. This operation is
    // intended to change the clusterVersion, but the current clusterVersion 
    // must be specified here.
    clusterVersion: ...
    
	// See top level cross cutting concerns for header details
    identity: ...
    connectionID: ...
    sequence: ...
    
	// The messageType should be SETUP
    messageType: SETUP
  }
  body {
    setup {
      // Required int64, needed to update the cluster version 
      // (otherwise request will be treated as a different Setup operation)
      // This is the clusterVersion being set on the device.
      newClusterVersion: 1
    }
  }
}
hmac: ""
```

**Response Message**

```
command {
  header {
    ackSequence: ...
    // The messageType should be SETUP_RESPONSE
    messageType: SETUP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
hmac: ""
```

### Set Pin

### Instant Secure Erase
This operation should be used to erase all stored data from the device. **This operation is currently neither instant nor secure. In future versions of the application, it will be both.**

**Request Message**

```
command {
  header {
  	// See top level cross cutting concerns for header details
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be SETUP
    messageType: SETUP
  }
  body {
    setup {
      // Required bool, defaults to false if omitted. 
      // Must be true for this request to be treated as an ISE.
      instantSecureErase: true
    }
  }
}
hmac: ""
```

**Response Message**

```
command {
  header {
    ackSequence: ...
    // The messageType should be SETUP_RESPONSE
    messageType: SETUP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
hmac: ""
```


### Firmware Download
This operation should be used load new firmware on the device.

**Request Message**

```
command {
  header {
  	// See top level cross cutting concerns for header details
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
  	// The messageType should be SETUP
    messageType: SETUP
  }
  body {
    setup {
      // Required bool, must be present and true to indicate that this is 
      // a firmware download operation.
      // Indicates that the value (in the Kinetic PDU) will contain the firmware
      firmwareDownload: true
    }
  }
}
hmac: ""
```

The value field in the Kinetic PDU (describe above) will contain the firmware payload.

**Response Message**

```
command {
  header {
    ackSequence: ...
    // The messageType should be SETUP_RESPONSE
    messageType: SETUP_RESPONSE
  }
  status {
    code: SUCCESS
  }
}
hmac: ""
```


## Administration

### Security
The security operation allows administrators to specify ACLs, granting access to specific operations. Some semantics of the Security operation are noteworthy:

* A `identity` has one ACL, and an ACL only applies to one `identity`. They have a one-to-one relationship.
* An ACL list cannot be updated, only set. Each request to SECURITY with a well-formed security body will overwrite the existing setup.
* To make a Secuirty operation (set ACLs) the requesting identity must have an applicable scope with a SECURITY permission.


To set the ACL for a identity (or many identities), a request like the following could be sent. See the Access Control section above for further explanation of the ACL message.

**Request Message**

```
command {
  header {
  	// See top level cross cutting concerns for header details
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    
    // messageType should be SECURITY
    messageType: SECURITY
  }
  body {
    // The security message must be present and contain at least one acl 
    // message. Multiple are allowed but only one can be specified per identity.
    // Note that security message overwrites the stored ACL list entirely, 
    // no updating is supported.
    security {
      acl {
        // Required int64, the identity this ACL applies to
        identity: 1
        // Required bytes, the identity's HMAC key, a shared secret
        key: "...."
        // Required HMACAlgorithm, the algorithm used to compute the HMAC for 
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
hmac: "..."

```


**Response Message**

```
command {
  header {
    ackSequence: ...
    
    // messageType should be SECURITY_RESPONSE
    messageType: SECURITY_RESPONSE
  }
  status {
  	// If successful, code will be SUCCESS
    code: SUCCESS
  }
}
hmac: ""
```

Error Cases:

* `code=NOT_AUTHORIZED` if the requesting identity does not have the `SECURITY` permission for an applicable scope.
* `code=NO_SUCH_HMAC_ALGORITHM` if an `acl` message has an `hmaclAlgorithm` value which is invalid.
* `code=INTERNAL_ERROR` (in the future, this code will be changed)
	* if an offset is provided which is less than zero
	* if there are no permissions provided in a scope
	* if one of the permissions provided is invalid (e.g. Permission.INVALID)


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
command {
  header {
    clusterVersion: ...
    identity: ...
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
hmac: "..."
```

**Respose Message**

```
command {
  header {
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
      	// Required string, the name of the rescource being reported       
      	// For example: HDA, ENO, CPU...
        name: "..."
        // Required float, the value for this resource's utilization.
        // value will be between 0.00 and 1.00.
        value: 0.2
      }
      
      utilization {
        name: "...""
        value: ...
      }
      ...
      
      // Many temperature messages may be returned
      temperature {
      	// Required string, the name of the resource being reported
        name: "..."

		// Required float, the current temperature in degrees celcius
        current: 39.0
		// Required float, the current temperature in degrees celcius
        minimum: 5.0
        // Required float, the current temperature in degrees celcius
        maximum: 100.0
		// Required float, the current temperature in degrees celcius        
        target: 25.0
      }
	
	  // Only one configuration message will be included      
      configuration {
        // string, the vendor of the Kinetic Device. 
        vendor: "..."

        // string, the model of the Kinetic Device
        model: "..."

        // bytes, the serial number of the Kinetic Device
        serialNumber: "..."

        // string, the version of the kinetic software running on the device
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
        // int32, the port where the kinetic service is running
        port: ...
        // int32, the port where the kinetic service is running over SSL
        tlsPort: ...
        // string, he date this version of the kinetic service was compiled
        compilationDate: "..."
        // string, a checksum of the source code
        sourceHash: "..."
      }
      
      // There should be one statistics message per messageType (GET, PUT, etc)
      // The statistics messages aggregate statistics for each messageType.
      statistics {
        // Required MessageType, which messageType these statistics apply to
        messageType: PUT
        // Required sint64, how many times this messageType has been received
        count: ...
        // Required sint64, the sum length of all the value portion of the 
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
        // uint64
      	nominalCapacityInBytes: ...
      	// float
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
command {
  header {
    clusterVersion: ...
    identity: ...
    connectionID: ...
    sequence: ...
    messageType: PEER2PEERPUSH
  }
  body {
    p2pOperation {
      peer {
      	// Required string, the network address of the peer
        hostname: "..."
        // Required int32, the port on which the peer is running the Kinetic service
        port: ...
        // Optional boolean, defaults to false. 
        // Currently SSL is not supported so this must be false.
        tls: ...
      }
      operation {
      	// Required bytes, the key to copy from the source peer.
        key: ""

		// Optional bytes, the 
		version: "..."
		
		// Optional bool, defaults to false
		// If true, force write ignoring version
		force: ...
		
  		// Optional bytes, the key to use in the destination peer.
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
hmac: ""
```

**Response Message**

```
command {
  header {
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
hmac: ""
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
