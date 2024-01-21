# Electric

The InfiniteLimits EDM library.

Daniel Li <inflmts@gmail.com>

Song files are located in the `files` directory. Each filename is in the form
`<artist>.<title>.mp3`, where `<artist>` and `<title>` are identifiers
representing the artist and title, respectively, using only the characters
`0-9`, `a-z`, and `-`.

## tag.sh

`tag.sh` is the library autotagger. It takes information from `songs.txt` and
`artists.txt` to tag each music file with the appropriate song, artist, and
album name. It also removes any other metadata in the file. The identifiers in
these metadata files are the same as those used in the song filenames.

`tag.sh` can automatically populate these files with songs and artists that have
not been added yet. To do this, run `tag.sh` with the `--update-metadata`
option:

```
./tag.sh --update-metadata
```

When sufficient information is provided in the metadata files, `tag.sh` can be
used to tag the music files with the defined song, artist, and album names. To
do this, run `tag.sh` without arguments:

```
./tag.sh
```
