# Electric

The InfiniteLimits EDM library.

Daniel Li <inflmts@gmail.com>

All songs are located in the `store` directory. Each filename is in the form
`<artist>.<title>.mp3`, where `<artist>` and `<title>` are identifiers
representing the artist and title, respectively, using only the characters
`0-9`, `a-z`, and `-`.

## tags.sh

`tags.sh` is a simple autotagger that tags the mp3 files with a title and artist
based on filename. It requires `id3v2` to be installed. To use, specify the
directory containing the mp3 files as an argument:

```
./tags.sh store
```

Run `./tags.sh --help` for more options.
