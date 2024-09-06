# Electric Music Library

This is the InfiniteLimits EDM library, curated by Daniel Li.

## Manifest File Format

The manifest file is a text file located at `manifest.txt`.
There are two groups, `main` and `extra`, each corresponding to a music directory.
They must appear in the manifest file in that order.
Each group begins with a header line, where `group` is the name of the group:

```
[group]
```

Following the group header is one line for each song in the group:

```
artist title hash date
```

- `artist` is the artist ID.
- `title` is the title ID.
- `hash` is the MD5 hash of the audio file as a 32-character lowercase hexadecimal string.
- `date` is the date the song was added to the library in the format `YYYY-MM-DD`.

The file is sorted by artist ID and then title ID, both in ASCII order
(`-` sorts before digits, which sort before letters).
