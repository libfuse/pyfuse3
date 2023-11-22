import sys
import os.path
import logging
import pytest
import time
import gc

# Enable output checks
pytest_plugins = ('pytest_checklogs')

# Register false positives
@pytest.fixture(autouse=True)
def register_false_checklog_pos(reg_output):

    # DeprecationWarnings are unfortunately quite often a result of indirect
    # imports via third party modules, so we can't actually fix them.
    reg_output(r'(Pending)?DeprecationWarning', count=0)

    # Valgrind output
    reg_output(r'^==\d+== Memcheck, a memory error detector$')
    reg_output(r'^==\d+== For counts of detected and suppressed errors, rerun with: -v')
    reg_output(r'^==\d+== ERROR SUMMARY: 0 errors from 0 contexts')

def pytest_addoption(parser):
    group = parser.getgroup("general")
    group._addoption("--installed", action="store_true", default=False,
                     help="Test the installed package.")

    group = parser.getgroup("terminal reporting")
    group._addoption("--logdebug", action="append", metavar='<module>',
                     help="Activate debugging output from <module> for tests. Use `all` "
                          "to get debug messages from all modules. This option can be "
                          "specified multiple times.")

# If a test fails, wait a moment before retrieving the captured
# stdout/stderr. When using a server process, this makes sure that we capture
# any potential output of the server that comes *after* a test has failed. For
# example, if a request handler raises an exception, the server first signals an
# error to FUSE (causing the test to fail), and then logs the exception. Without
# the extra delay, the exception will go into nowhere.
@pytest.hookimpl(hookwrapper=True)
def pytest_pyfunc_call(pyfuncitem):
    outcome = yield
    failed = outcome.excinfo is not None
    if failed:
        time.sleep(1)

def pytest_configure(config):
    # If we are running from the source directory, make sure that we load
    # modules from here
    basedir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    if not config.getoption('installed'):
        pyfuse3_path = os.path.join(basedir, 'src')
        if (os.path.exists(os.path.join(basedir, 'setup.py')) and
            os.path.exists(os.path.join(basedir, 'src', 'pyfuse3', '__init__.pyx'))):
            sys.path.insert(0, pyfuse3_path)

        # Make sure that called processes use the same path
        pp = os.environ.get('PYTHONPATH', None)
        if pp:
            pp = '%s:%s' % (pyfuse3_path, pp)
        else:
            pp = pyfuse3_path
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
        warnings.simplefilter('default')

    # Configure logging. We don't set a default handler but rely on
    # the catchlog pytest plugin.
    logdebug = config.getoption('logdebug')
    root_logger = logging.getLogger()
    if logdebug is not None:
        logging.disable(logging.NOTSET)
        if 'all' in logdebug:
            root_logger.setLevel(logging.DEBUG)
        else:
            for module in logdebug:
                logging.getLogger(module).setLevel(logging.DEBUG)
    else:
        root_logger.setLevel(logging.INFO)
        logging.disable(logging.DEBUG)
    logging.captureWarnings(capture=True)

# Run gc.collect() at the end of every test, so that we get ResourceWarnings
# as early as possible.
def pytest_runtest_teardown(item, nextitem):
    gc.collect()
