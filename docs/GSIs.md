We have **2 GSIs**, plus the base table's own primary key — three distinct ways to query the same data:

| Index                        | Partition key | Sort key | Questions it answers                                                                                                                |
| ---------------------------- | ------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Base table** (primary key) | `Artist`      | `Song`   | "What songs does *Nirvana* have?" / "Does *Nirvana* have a song called *Come As You Are*?" / "List Nirvana's songs alphabetically." |
| **`Album-Index`** (GSI1)     | `Album`       | `Song`   | "What songs are on *Nevermind*?" / "Is *Come As You Are* on *Nevermind*?" / "List the tracklist of an album in song-title order."   |
| **`Song-Index`** (GSI2)      | `Song`        | `Artist` | "Who sings the song *Just a Girl*?" / "Every version of a song across different artists." / "List artists alphabetically for a given song title." |

The reason we need the two GSIs at all: the base table can only be queried efficiently by `Artist` (you must know the artist to get anything back without a full scan). `Album` and `Song` (as a partition key) aren't part of that key structure, so without a GSI, "everything on this album" or "who performed this song" would require a full table scan. Each GSI reindexes the table so one of those attributes becomes queryable as its own partition key — same underlying items, three different lookup angles. `Song-Index` in particular covers the most common real-world search pattern: looking a song up by title without already knowing who performed it.
