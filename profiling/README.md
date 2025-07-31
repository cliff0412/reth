## start
```sh
docker-compose -f docker-compose.op-profiling.yml up -d
docker-compose -f docker-compose.op-profiling.yml exec -it op-reth bash
./start_samply.sh
samply load profiles/profile-xxx.json.gz
```


## manually build image (if necessary)
```sh
docker build \
  --build-arg BUILD_PROFILE=profiling \
  --build-arg FEATURES="jemalloc-prof,asm-keccak" \
  --build-arg RUSTFLAGS="-C target-cpu=native" \
  -f DockerfileOpProfile \
  -t op-reth-profiling \
  ./..

docker build -f DockerfileDeployOp -t deploy-op ./..
```

## other profiling tools
- https://github.com/svenstaro/cargo-profiler
- https://crates.io/crates/gperftools
