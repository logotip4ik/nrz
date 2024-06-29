# nrz

Same as nrr or nrn, but even faster.

## What to try out ?

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
hyperfine --warmup=5 --output=pipe '../release/nrn start' './nrr start' 'nrz start'

Benchmark 1: ../release/nrn start
  Time (mean ± σ):      44.1 ms ±   1.7 ms    [User: 25.7 ms, System: 10.1 ms]
  Range (min … max):    41.8 ms …  47.9 ms    59 runs
 
Benchmark 2: ./nrr start
  Time (mean ± σ):      31.9 ms ±   0.6 ms    [User: 21.2 ms, System: 6.5 ms]
  Range (min … max):    30.9 ms …  33.8 ms    83 runs
 
Benchmark 3: nrz start
  Time (mean ± σ):      29.8 ms ±   0.6 ms    [User: 20.6 ms, System: 5.7 ms]
  Range (min … max):    28.7 ms …  31.2 ms    86 runs
 
Summary
  nrz start ran
    1.07 ± 0.03 times faster than ./nrr start
    1.48 ± 0.06 times faster than ../release/nrn start
```
