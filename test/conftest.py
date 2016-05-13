import sys
import os.path
import logging
import gc

# Enable output checks
pytest_plugins = ('pytest_checklogs')

def pytest_addoption(parser):
    group = parser.getgroup("general")
    group._addoption("--installed", action="store_true", default=False,
                     help="Test the installed package.")

    group = parser.getgroup("terminal reporting")
    group._addoption("--logdebug", action="append", metavar='<module>',
                     help="Activate debugging output from <module> for tests. Use `all` "
                          "to get debug messages from all modules. This option can be "
                          "specified multiple times.")

def pytest_configure(config):
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
