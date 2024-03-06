# tailwind-config-reporter

Some unofficial scripts to try and analyze how people use [Tailwind CSS](https://tailwindcss.com/) (no affiliation). You can see the latest analysis results from the [`tailwind-config-dataset` repository](https://github.com/dpb587/tailwind-config-dataset). This is more of a utilitarian script approach, not some super efficient and elegant system. Here is the general process and more interesting components:

* [customsearch](./customsearch) uses the GitHub API to discover public repositories and paths which contain Tailwind-related projects.
* [worker](./worker) uses a Docker container to clone, install, and analyze a public git repository. A private container network restricts outbound access, and a [proxy](./worker-proxy/squid.conf) enables limited network access for well-known package installations with heavy local caching.
  * [squash-package](./worker/squash-package.mjs) is used to try and only install dependencies needed to compile the `tailwind.config.*` file. If it fails, install tries again with the original `package.json` dependencies.
  * [two](./worker/tailwind.config.exporter3.mjs) [methods](./worker/tailwind.config.exporter2.cjs) are used to try and export the `tailwind.config.*` file depending on the `tailwindcss` package being used. It is run for both a minimal config file to capture a baseline configuration, and then again with the user customizations.
* [transformer](./transformer) runs additional analysis on the files and metadata captured by a worker.
  * [tailwind-changes-analyzer](./transformer/tailwind-changes-analyzer) compares the baseline and effective Tailwind configurations to generate more meaningful records about what was customized.
* [aggregator](./aggregator) collects all the transformed results into a SQLite database.
  * [exporter](./aggregator/exporter) runs some common queries against the database and generates the Markdown data shown in the [`tailwind-config-dataset` repository](https://github.com/dpb587/tailwind-config-dataset).

I'm not a particular expert in Tailwind nor Node+JavaScript's confusing matrix of toolchains and conventions, so there might be some odd assumptions. Many of these scripts and snippets are cobbled together from past work and experiments; your mileage may vary. My goal wasn't 100% Tailwind coverage and build success which seems difficult given the broad userspace nature. Plus this was just kind of an experiment. There are a few, repeated build and analysis errors that I think could still be resolved.

## Rough Technical Notes

Probably want to run this on a short-lived VM since it runs arbitrary-ish user code (even though it should be fairly secure within the Docker container). The following are needed:

* [Go](https://go.dev/dl/) - for the repository search
* [Docker](https://docs.docker.com/engine/install/) (or equivalent) - for running the proxy and worker
* [jq](https://jqlang.github.io/jq/download/) - for much of the data transformations and utilities
* [SQLite](https://sqlite.org/download.html) - must support extensions which may not be available in default OS packages
* [sqlean](https://github.com/nalgeon/sqlean/releases) (expanded into `./mnt/sqlite/sqlean`) - SQLite extension for decoding values during import

A local directory for tracking results...

```
mkdir -p mnt/dataset
```

Build the container images, create the internal network, and run the proxy server...

```
./init.sh
```

Run a single analysis...

```
./worker/run-task-docker.sh github.com/tailwindlabs/headlessui main playgrounds/react
#                           repository                        branch   [subdirectory]
```

Or query and then analyze a full list from GitHub...

```
( cd customsearch && GITHUB_API_TOKEN=a1b2c3d4... go run . )
( echo '#!/bin/sh' ; jq -sr 'sort_by(.CachedData.StargazersCount) | reverse | map(select(.Valid))[] | . as $repo | .FileMatches // [] | map(select(.Valid))[] | @sh "./worker/run-task-docker.sh \($repo.Name) \($repo.CachedData.DefaultBranchName) \(.Path | split("/")[0:-1] | join("/"))"' < mnt/dataset/seed/github.jsonl ) > run-github-seed.sh && chmod +x run-github-seed.sh
./run-github-seed.sh
```

After running, compile all the captured analysis data...

```
./transformer/run.sh
./aggregator/run.sh
```

Generate and review the default Markdown reports...

```
./aggregator/exporter/run.sh
open ./mnt/dataset/analysis/README.md
```

Manually access the data in the SQLite database and run custom queries...

```
sqlite3 mnt/dataset/aggregate/db.sqlite
> .tables
> .schema tailwind_changes
```

Manually use a container for debugging...

```
docker run \
  -it \
  --rm \
  --workdir /home/node \
  --network tailwind-config-reporter-worker \
  -e http_proxy=http://test:ok@172.18.0.2:3128 \
  -e HTTP_PROXY=http://test:ok@172.18.0.2:3128 \
  -e https_proxy=http://test:ok@172.18.0.2:3128 \
  -e HTTPS_PROXY=http://test:ok@172.18.0.2:3128 \
  tailwind-config-reporter-worker
$ yarn config set httpProxy http://test:ok@172.18.0.2:3128
$ yarn config set httpsProxy http://test:ok@172.18.0.2:3128
```

## Ideas

* this only looks at the user-configuration, so it doesn't take into account what features actually end up being used; it might be interesting to have another step which generates the actual stylesheet (assuming content and files are present)
  * related, tools which can reverse engineer a generated stylesheet and possibly content files to understand the effective Tailwind configuration that might have been used for it; seems like it'd be a more accurate reflection of usage
* could probably add plugin support; there are some initial pieces, but I haven't really looked at the data and I think there are some cases where the baseline configuration doesn't currently capture enough about it
* probably continue to run `customsearch` to further expand the dataset as GitHub activity and pagination changes expose more public sources
* maybe extract additional metadata about values and CSS functions being used
* a more complicated data solution would help surface individual repository examples behind some of the numbers; useful for investigating interesting configurations that stand out

## License

[MIT License](./LICENSE)
