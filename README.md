# nrz

Same as [nrr](https://github.com/ryanccn/nrr) or [nrn](https://github.com/logotip4ik/nrn), but even faster.

## Want to try out ?

You can build it yourself, or use latest artifacts from [build ci](https://github.com/logotip4ik/nrz/actions/workflows/build.yml).

To build `nrz`:

1. Clone this repo

2. Build `nrz` with (you will need zig installed):

    ```sh
    zig build --release=fast --summary all -Doptimize=ReleaseFast
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
  Time (mean ± σ):      12.2 ms ±   0.3 ms    [User: 3.0 ms, System: 3.6 ms]
  Range (min … max):    10.4 ms …  13.9 ms    234 runs
 
Benchmark 2: ./nrr empty
  Time (mean ± σ):       4.8 ms ±   0.2 ms    [User: 0.8 ms, System: 1.5 ms]
  Range (min … max):     3.2 ms …   5.8 ms    641 runs
 
Benchmark 3: nrz empty
  Time (mean ± σ):       2.9 ms ±   0.3 ms    [User: 0.4 ms, System: 0.9 ms]
  Range (min … max):     2.2 ms …   3.6 ms    891 runs
 
Benchmark 4: node --run empty
  Time (mean ± σ):      18.6 ms ±   0.2 ms    [User: 12.9 ms, System: 2.2 ms]
  Range (min … max):    17.6 ms …  20.0 ms    159 runs
 
Summary
  nrz empty ran
    1.63 ± 0.19 times faster than ./nrr empty
    4.14 ± 0.46 times faster than ../release/nrn empty
    6.35 ± 0.69 times faster than node --run empty
```
