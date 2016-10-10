from h import i18n
from pyramid.view import (view_config)

_ = i18n.TranslationStringFactory(__package__)


@view_config(route_name='termsofservice', request_method='GET',
             renderer='annotran:templates/terms-of-service.html.jinja2')
def terms_of_service(context, request):
    """Display the terms of service."""
    return {'support_address': Shared.support_address}


def includeme(config):
    """
    Pyramid includeme setup method to add routes
    :param config: the configuration supplied by pyramid
    :return: None
    """
    config.add_route('termsofservice', '/terms-of-service')
    config.scan(__name__)


class Shared(object):
    def __init__(self):
        pass

    support_address = ""
