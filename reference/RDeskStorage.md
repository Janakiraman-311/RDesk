# RDesk Storage Manager

Provides a lightweight, JSON-backed key-value store for application
state, preferences, and settings. Handles multi-user data isolation
automatically.

## Methods

### Public methods

- [`RDeskStorage$new()`](#method-RDeskStorage-new)

- [`RDeskStorage$set()`](#method-RDeskStorage-set)

- [`RDeskStorage$get()`](#method-RDeskStorage-get)

- [`RDeskStorage$remove()`](#method-RDeskStorage-remove)

- [`RDeskStorage$clear()`](#method-RDeskStorage-clear)

- [`RDeskStorage$keys()`](#method-RDeskStorage-keys)

- [`RDeskStorage$path()`](#method-RDeskStorage-path)

- [`RDeskStorage$clone()`](#method-RDeskStorage-clone)

------------------------------------------------------------------------

### Method `new()`

Initialize a new RDeskStorage manager

#### Usage

    RDeskStorage$new(app_name, storage_type = "local")

#### Arguments

- `app_name`:

  Application name

- `storage_type`:

  Storage type: "roaming", "local", or "shared"

------------------------------------------------------------------------

### Method `set()`

Set a key-value pair in storage

#### Usage

    RDeskStorage$set(key, value)

#### Arguments

- `key`:

  Character string key

- `value`:

  Value to store (must be JSON serializable)

#### Returns

The RDeskStorage instance (invisible)

------------------------------------------------------------------------

### Method [`get()`](https://rdrr.io/r/base/get.html)

Retrieve a value from storage

#### Usage

    RDeskStorage$get(key, default = NULL)

#### Arguments

- `key`:

  Character string key

- `default`:

  Default value to return if the key is not found

#### Returns

The stored value, or the default value

------------------------------------------------------------------------

### Method [`remove()`](https://rdrr.io/r/base/rm.html)

Remove a key from storage

#### Usage

    RDeskStorage$remove(key)

#### Arguments

- `key`:

  Character string key

#### Returns

The RDeskStorage instance (invisible)

------------------------------------------------------------------------

### Method `clear()`

Clear all data in this storage domain

#### Usage

    RDeskStorage$clear()

#### Returns

The RDeskStorage instance (invisible)

------------------------------------------------------------------------

### Method `keys()`

List all keys currently in storage

#### Usage

    RDeskStorage$keys()

#### Returns

Character vector of keys

------------------------------------------------------------------------

### Method `path()`

Get the directory path containing the storage file

#### Usage

    RDeskStorage$path()

#### Returns

Character string directory path

------------------------------------------------------------------------

### Method `clone()`

The objects of this class are cloneable with this method.

#### Usage

    RDeskStorage$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.
