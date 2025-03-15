# nrz

Same as [nrr](https://github.com/ryanccn/nrr) or [nrn](https://github.com/logotip4ik/nrn), but even faster.

## Want to try out ?

Download latest build artifact from [build ci](https://github.com/logotip4ik/nrz/actions/workflows/build.yml).

<details>
<summary>To build `nrz` localy</summary>

1. Clone this repo

2. Build `nrz` with (you will need zig installed):

    ```sh
    zig build --release=fast --summary all -Doptimize=ReleaseFast
    ```

3. Add `<repo dir>/zig-out/bin` to `PATH`
</details>

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

## Completions

Nrz can also autocomplete scripts for you, to enable autocomplete, add to your shell config file:

```bash
# For zsh
source <(nrz --cmp=Zsh)

# Bash
source <(nrr --cmp=Bash)

# Fish
source (nrr --cmp=Fish | psub)
```

> Note: i can't verify if Bash and Fish autocompletes are working, please let me know if they aren't
> by creating an issue

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
$ hyperfine "./nrr empty" "./nrz empty" "npm run empty" "node --run empty" --shell=none --output=pipe
Benchmark 1: ./nrr empty
  Time (mean ± σ):       5.2 ms ±   0.5 ms    [User: 1.3 ms, System: 1.6 ms]
  Range (min … max):     4.5 ms …  11.3 ms    264 runs

Benchmark 2: ./nrz empty
  Time (mean ± σ):       3.6 ms ±   0.2 ms    [User: 0.7 ms, System: 1.1 ms]
  Range (min … max):     2.6 ms …   4.5 ms    828 runs

Benchmark 4: npm run empty
  Time (mean ± σ):     108.3 ms ±   1.1 ms    [User: 73.6 ms, System: 12.5 ms]
  Range (min … max):   105.3 ms … 110.2 ms    27 runs

Benchmark 5: node --run empty
  Time (mean ± σ):      32.8 ms ±   0.4 ms    [User: 22.3 ms, System: 2.7 ms]
  Range (min … max):    32.0 ms …  34.3 ms    87 runs

Summary
  ./nrz empty ran
    1.42 ± 0.15 times faster than ./nrr empty
    8.98 ± 0.46 times faster than node --run empty
   29.68 ± 1.52 times faster than npm run empty

$ ./nrr --version
nrr 0.9.2
$ nrz --version
nrz 1.0.4
$ node --version
v22.11.0
$ npm --version
10.9.0
```

> Benched on MacBook M3 Pro, Sequoia 15.2
