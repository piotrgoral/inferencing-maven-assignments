import logging


def configure_logging() -> None:
    """Set up a basic console logger if none is configured."""
    if logging.getLogger().handlers:
        return
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
