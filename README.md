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
    "log": "echo $PATH",
    "empty": ""
  }
}
```
</details>

```sh
hyperfine --warmup=5 --output=pipe --shell=none '../release/nrn empty' './nrr empty' 'nrz empty' 'node --run empty'

Benchmark 1: ../release/nrn empty
  Time (mean ± σ):      11.8 ms ±   0.3 ms    [User: 3.0 ms, System: 3.4 ms]
  Range (min … max):    10.9 ms …  13.3 ms    226 runs
 
Benchmark 2: ./nrr empty
  Time (mean ± σ):       4.6 ms ±   0.3 ms    [User: 0.8 ms, System: 1.5 ms]
  Range (min … max):     3.4 ms …   5.2 ms    657 runs
 
Benchmark 3: nrz empty
  Time (mean ± σ):       3.4 ms ±   0.1 ms    [User: 0.4 ms, System: 1.0 ms]
  Range (min … max):     2.6 ms …   4.3 ms    867 runs
 
Benchmark 4: node --run empty
  Time (mean ± σ):      18.8 ms ±   0.3 ms    [User: 13.0 ms, System: 2.3 ms]
  Range (min … max):    18.2 ms …  20.1 ms    159 runs
 
Summary
  nrz empty ran
    1.35 ± 0.10 times faster than ./nrr empty
    3.45 ± 0.16 times faster than ../release/nrn empty
    5.47 ± 0.23 times faster than node --run empty
~/dev/nrn/playground (main) $
```
