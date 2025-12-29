# How to run/develop pyfuse3 from Git

To run unit tests, build the documentation, and make changes to pyfuse3, the recommended procedure is
to create a virtual environment and install pyfuse3, build dependencies, and development tools into
this environment.

You can do this using a tool like [uv](https://docs.astral.sh/uv/getting-started/installation/) or
by hand as follows:

```sh
$ python3 -m venv .venv   # create the venv
$ . .venv/bin/activate    # activate it
$ pip install --upgrade pip # upgrade pip
$ pip install ".[dev]"  # install build dependencies
$ pip install --no-build-isolation --editable .  # install pyfuse3 in editable mode
```

As long as the venv is active, you can run tests with

```sh
$ pytest test/
```

and build the HTML documentation and manpages with:
```sh
$ sphinx-build -b html rst doc/html
```

