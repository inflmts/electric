# Electric Music Library

_Daniel Li_

This is a collection of electronic music that I like,
extracted from various places on the internet.

The purpose of this project is to provide a way to automatically normalize audio files
and to make it easy to synchronize music between devices.

The library is divided into two groups, `core` and `extra`.
The `core` group contains songs for regular listening.
They can be shuffled to produce a sort of all-purpose playlist.
The majority of songs fall into this group.
The `extra` group contains songs that are not intended for regular listening,
usually because they're kind of stupid.
However, they have significant value and are useful on occasion.

## Manifest File Format

The manifest file is a text file located at `manifest.txt`.
Each group in the file begins with a header line (`group` is the name of the group):

```
[group]
```

Following the group header is one line for each song in the group.
Each line is broken into space-separated fields:

```
artist title date file_hash tag_hash
```

- `artist` is the artist ID.
- `title` is the title ID.
- `date` is the date the song was added to the library in the format `YYYY-MM-DD`.
- `file_hash` is the MD5 hash of the file as a 32-character lowercase hexadecimal string.
- `tag_hash` is the CRC32 hash of the file tags as a 8-character lowercase hexadecimal string.

The file is sorted by artist ID and then title ID, both in ASCII order
(`-` sorts before digits, which sort before letters).
