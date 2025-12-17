# Electric Music Library

Curated by Daniel Li.

> Is that all you've got?
>
> &mdash; Teminite & Boom Kitty, _The Master_

## What is it?

Electric is a collection of electronic music that I like,
bought/extracted/ripped from various places on the internet.
The purpose of this project is to provide a way to automatically normalize
audio files and to make it easy to synchronize music between devices.
This repository contains:

- `electric`, the manager program
- `catalog.txt`, a list of all the songs in the library
- `art.svg`, the cover art made by me

The music files themselves are not stored in the repository, instead they are
managed with `electric`.

Dependencies for `electric`:

- Python 3.8 (required)
- ffmpeg (for import)
- adb (for transferring files to an Android device)

Documentation for `electric` will appear here once the interface becomes more
stable.

## Catalog File Format

`catalog.txt` lists all the songs in the library. The syntax is very strict
and designed to be parsed and written by a machine. The format is one song per
line. Blank lines are not permitted. Comments are not supported.
Each line has the following format:

```
id date artist title mhash
```

- `id` is the song ID, as a positive integer without leading zeroes. IDs must
  start with 1 and increase consecutively, ie. the ID must match the line
  number.

- `date` is the date the song was added to the library in the format
  `YYYY-MM-DD`.

- `artist` is a comma-separated list of artist names.
  The first name in the list will be used for the `TPE1` tag.

- `title` is the song title, used for the `TIT2` tag.

- `mhash` is the SHA256 hash of the MP3 data, including the Xing/Info header
  but **excluding** the ID3 tag.

The artist names and song titles may only include lowercase letters, digits,
dashes (-), and hash characters (#). They must not begin or end with a dash or
contain consecutive dashes. They are converted to tags by translating
lowercase to uppercase and replacing dashes with spaces.
