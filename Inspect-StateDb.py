import pathlib
import sqlite3

path = pathlib.Path.home() / ".codex" / "state_5.sqlite"
db = sqlite3.connect(f"file:{path.as_posix()}?mode=ro", uri=True)
for (name,) in db.execute("select name from sqlite_master where type='table' order by name"):
    print(name)

print("THREAD_COLUMNS")
print(list(db.execute("pragma table_info(threads)")))
print("RECENT_THREADS")
columns = [row[1] for row in db.execute("pragma table_info(threads)")]
for row in db.execute("select * from threads order by updated_at desc limit 10"):
    print(dict(zip(columns, row)))
