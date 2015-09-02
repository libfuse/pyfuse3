import sys
import os.path
import logging
import pytest
import gc

# Converted to autouse fixture below if capture is activated
def check_test_output(request, capfd):
    request.capfd = capfd
    def raise_on_exception_in_out():
        # Peek at captured output
        (stdout, stderr) = capfd.readouterr()
        sys.stdout.write(stdout)
        sys.stderr.write(stderr)

        if ('exception' in stderr.lower()
            or 'exception' in stdout.lower()):
            raise AssertionError('Suspicious output to stderr')

    request.addfinalizer(raise_on_exception_in_out)


def pytest_addoption(parser):
    group = parser.getgroup("general")
    group._addoption("--installed", action="store_true", default=False,
                     help="Test the installed package.")

    group = parser.getgroup("terminal reporting")
    group._addoption("--logdebug", action="store_true", default=False,
                     help="Activate debugging output.")

def pytest_configure(config):
    # Enable stdout and stderr analysis, unless output capture is disabled
    if config.getoption('capture') != 'no':
        global check_test_output
        check_test_output = pytest.fixture(autouse=True)(check_test_output)

    # If we are running from the source directory, make sure that we load
    # modules from here
    basedir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    if not config.getoption('installed'):
        llfuse_path = os.path.join(basedir, 'src')
        if (os.path.exists(os.path.join(basedir, 'setup.py')) and
            os.path.exists(os.path.join(basedir, 'src', 'llfuse.pyx'))):
            sys.path.insert(0, llfuse_path)

        # Make sure that called processes use the same path
        pp = os.environ.get('PYTHONPATH', None)
        if pp:
            pp = '%s:%s' % (llfuse_path, pp)
        else:
            pp = llfuse_path
        os.environ['PYTHONPATH'] = pp

    try:
        import faulthandler
    except ImportError:
        pass
    else:
        faulthandler.enable()

    # When running from VCS repo, enable all warnings
    if os.path.exists(os.path.join(basedir, 'MANIFEST.in')):
        import warnings
        warnings.resetwarnings()
        warnings.simplefilter('error')

    logdebug = config.getoption('logdebug')
    if logdebug:
        root_logger = logging.getLogger()
        formatter = logging.Formatter('%(asctime)s.%(msecs)03d %(threadName)s '
                                      '%(funcName)s: %(message)s',
                                      datefmt="%H:%M:%S")
        handler = logging.StreamHandler(sys.stdout)
        handler.setLevel(logging.DEBUG)
        handler.setFormatter(formatter)
        root_logger.addHandler(handler)
        root_logger.setLevel(logging.DEBUG)

# Run gc.collect() at the end of every test, so that we get ResourceWarnings
# as early as possible.
def pytest_runtest_teardown(item, nextitem):
    gc.collect()
