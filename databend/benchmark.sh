#!/bin/bash

curl -LJO 'https://github.com/datafuselabs/databend/releases/download/v0.9.53-nightly/databend-v0.9.53-nightly-x86_64-unknown-linux-musl.tar.gz'
tar xzvf 'databend-v0.9.53-nightly-x86_64-unknown-linux-musl.tar.gz'
 
cat > config.toml << CONF
[storage]
type = "fs"

[storage.fs]
data_path = "./_data"

[meta]
embedded_dir = "./.databend/meta_embedded"
CONF

# databend starts with embedded meta service
./bin/databend-query -c config.toml > query.log 2>&1 &

sleep 5

# Load the data
# Docs: https://databend.rs/doc/use-cases/analyze-hits-dataset-with-databend
curl 'http://default@localhost:8124/' --data-binary @create.sql

wget --continue 'https://datasets.clickhouse.com/hits_compatible/hits.tsv.gz'
gzip -d hits.tsv.gz

## Aws gp2 write performance is not stable, we must load the data when disk's write around ~500MB/s (Don't know much about the rules of gp2)
time curl -XPUT 'http://root:@127.0.0.1:8000/v1/streaming_load' -H 'insert_sql: insert into hits FILE_FORMAT = (type = TSV)' -F 'upload=@"./hits.tsv"'

## in c5.4x large, it's 368s
# {"id":"17477ed9-9f1a-46d9-b6cf-12a5971f4450","state":"SUCCESS","stats":{"rows":99997497,"bytes":74807831229},"error":null,"files":["hits.tsv"]}
# real    6m8.975s
# user    0m4.327s
# sys     0m36.185s

## in c6a.4xlarge it's ~360s
# {"id":"f7506581-a4da-4684-850c-4bd03530314d","state":"SUCCESS","stats":{"rows":99997497,"bytes":74807831229},"error":null,"files":["hits.tsv"]}
# real    5m57.800s
# user    0m2.106s
# sys     0m33.507s

## in c6a.metal it's ~70s
# {"id":"2564bd91-1b36-4cf2-a95e-de46c5aff0c6","state":"SUCCESS","stats":{"rows":99997497,"bytes":74807831229},"error":null,"files":["hits.tsv"]}
# real    1m10.347s
# user    0m0.953s
# sys     0m20.401s



## check data is correct
curl 'http://default@localhost:8124/' --data-binary "select count() from hits"

du -bcs _data
# 20922561953     _data
# 20922561953     total

# If you wants to get the data size(without metadata and indexes)
# curl 'http://default@localhost:8124/' --data-binary "select humanize_size(bytes_compressed)  from fuse_snapshot('default', 'hits') order by timestamp desc limit 1"
# 18.48 GiB

./run.sh 2>&1 | tee log.txt
