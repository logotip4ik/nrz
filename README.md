# nrz

Same as [nrr](https://github.com/ryanccn/nrr) or [nrn](https://github.com/logotip4ik/nrn), but even faster.

## Want to try out ?

1. Clone this repo

2. Build `nrz` with (you will need zig installed):

    ```sh
    zig build --release=fast
    ```

3. Add `<repo dir>/zig-out/bin` to `PATH`

## Usage

```sh
nrz dev --host
```

This will run `dev` command from closest `package.json` and pass `--host` and option (it will forward
everything you handle it).

```sh
nrz eslint ./src
```

This will run `eslint` from closest `node_modeules/.bin/` folder and pass `./src` as arg.

## Benchmark

<details>
<summary>package.json</summary>

```json
{
  "scripts": {
    "start": "node index.js",
    "log": "echo $PATH"
  }
}
```
</details>

```sh
hyperfine --warmup=5 --output=pipe '../release/nrn start' './nrr start' 'nrz start' 'node --run start'

Benchmark 1: ../release/nrn start
  Time (mean ± σ):      36.9 ms ±   0.5 ms    [User: 22.5 ms, System: 7.4 ms]
  Range (min … max):    35.8 ms …  38.1 ms    74 runs
 
Benchmark 2: ./nrr start
  Time (mean ± σ):      27.4 ms ±   0.4 ms    [User: 19.0 ms, System: 3.7 ms]
  Range (min … max):    26.6 ms …  28.4 ms    94 runs
 
Benchmark 3: nrz start
  Time (mean ± σ):      25.8 ms ±   0.4 ms    [User: 18.6 ms, System: 3.1 ms]
  Range (min … max):    24.9 ms …  26.8 ms    103 runs
 
Benchmark 4: node --run start
  Time (mean ± σ):      40.8 ms ±   0.5 ms    [User: 31.3 ms, System: 4.5 ms]
  Range (min … max):    39.6 ms …  42.1 ms    67 runs
 
Summary
  nrz start ran
    1.06 ± 0.02 times faster than ./nrr start
    1.43 ± 0.03 times faster than ../release/nrn start
    1.58 ± 0.03 times faster than node --run start
```
