'''

Copyright (c) 2013-2014 Hypothes.is Project and contributors

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
'''
#monkey patching of hypothesis methods

from jinja2 import Environment, PackageLoader
from annotran.languages import models
from h import presenters
from h.api import search
from h.api import uri
from pyramid import renderers
import collections
import h
from pyramid import httpexceptions as exc
from h.api import transform


#annotran's version of h.groups.views._read_group
def _read_group(request, group, language=None):
    """Return the rendered "Share this group" page.

    This is the page that's shown when a user who is already a member of a
    group visits the group's URL.

    """
    url = request.route_url('group_read', pubid=group.pubid, slug=group.slug)


    #language = models.Language.get_by_groupubid(group.pubid)

    result = search.search(request,
                           private=False,
                           params={"group": group.pubid, "limit": 1000})
    annotations = [presenters.AnnotationHTMLPresenter(models.Annotation(a))
                   for a in result['rows']]

    # Group the annotations by URI.
    # Create a dict mapping the (normalized) URIs of the annotated documents
    # to the most recent annotation of each document.
    annotations_by_uri = collections.OrderedDict()
    for annotation in annotations:
        normalized_uri = uri.normalize(annotation.uri)
        if normalized_uri not in annotations_by_uri:
            annotations_by_uri[normalized_uri] = annotation
            if len(annotations_by_uri) >= 25:
                break

    document_links = [annotation.document_link
                      for annotation in annotations_by_uri.values()]

    template_data = {
        'group': group, 'group_url': url, 'document_links': document_links}

    return renderers.render_to_response(
        renderer_name='h:templates/groups/share.html.jinja2',
        value=template_data, request=request)

#annotran's version of h.session.model
def model(request):
    session = {}
    session['csrf'] = request.session.get_csrf_token()
    session['userid'] = request.authenticated_userid
    session['groups'] = h.session._current_groups(request)
    session['features'] = h.session.features.all(request)
    session['languages'] = _current_languages(request)
    session['preferences'] = {}
    user = request.authenticated_user
    if user and not user.sidebar_tutorial_dismissed:
        session['preferences']['show_sidebar_tutorial'] = True
    return session

#annotran's version of h.client._angular_template_context
def _angular_template_context_ext(name):
    """Return the context for rendering a 'text/ng-template' <script>
       tag for an Angular directive.
    """
    jinja_env_ext = Environment(loader=PackageLoader(__package__, 'templates'))
    jinja_env = h.client.jinja_env
    if (name == 'user_list' or name == 'language_list' or name == 'top_bar'):
        angular_template_path = 'client/{}.html'.format(name)
        content, _, _ = jinja_env_ext.loader.get_source(jinja_env_ext,
                                                    angular_template_path)
    else:
        angular_template_path = 'client/{}.html'.format(name)
        content, _, _ = jinja_env.loader.get_source(jinja_env,
                                                angular_template_path)
    return {'name': '{}.html'.format(name), 'content': content}

#annotran's version of h.api.groups.set_group_if_reply
def set_group_if_reply(annotation):
    """If the annotation is a reply set its group to that of its parent.

    If the annotation is a reply to another annotation (or a reply to a reply
    and so on) then it always belongs to the same group as the original
    annotation. If the client sent any 'group' field in the annotation we will
    just overwrite it!

    """
    def is_reply(annotation):
        """Return True if this annotation is a reply."""
        if annotation.get('references'):
            return True
        else:
            return False

    if not is_reply(annotation):
        return

    # Get the top-level annotation that this annotation is a reply
    # (or a reply-to-a-reply etc) to.
    top_level_annotation_id = annotation['references'][0]
    top_level_annotation = models.Annotation.fetch(top_level_annotation_id)

    # If we can't find the top-level annotation, there's nothing we can do, and
    # we should bail.
    if top_level_annotation is None:
        return

    if 'group' in top_level_annotation:
        annotation['group'] = top_level_annotation['group']
        annotation['group2'] = top_level_annotation['group']
        annotation['language'] = top_level_annotation['language']
    else:
        if 'group' in annotation:
            del annotation['group']

def _language_sort_key(language):
    """Sort private languages for the session model list"""

    # languages are sorted first by name but also by ID
    # so that multiple languages with the same name are displayed
    # in a consistent order in clients
    return (language.name.lower(), language.pubid)

def _current_languages(request):
    """Return a list of the groups the current user is a member of.

    This list is meant to be returned to the client in the "session" model.

    """
    '''        'group': group, 'group_url': url, 'document_links': document_links}

        group = {'name': 'Public', 'id': '__world__', 'public': True}
        return None
    else:
        group = h.groups.models.Group.get_by_pubid(groupubid)
    '''

    languages = []
    userid = request.authenticated_userid
    if userid is None:
        return languages
    user = request.authenticated_user
    # if user is None or get_group(request) is None:
    #   return languages
    # return languages for all groups for that particular user
    for group in user.groups:
        for language in group.languages:
            languages.append({
                'groupubid': group.pubid,
                'name': language.name,
                'id': language.pubid,
                'url': request.route_url('language_read',
                                         pubid=language.pubid, groupubid=group.pubid),
            })

    return languages

def get_group(request):
    if request.matchdict.get('pubid') is None:
        return None
    pubid = request.matchdict["pubid"]
    group = h.groups.models.Group.get_by_pubid(pubid)
    if group is None:
        raise exc.HTTPNotFound()
    return group

#annotran's version of h.api.groups.set_group_if_reply
def set_group_if_reply(annotation):
    """If the annotation is a reply set its group to that of its parent.

    If the annotation is a reply to another annotation (or a reply to a reply
    and so on) then it always belongs to the same group as the original
    annotation. If the client sent any 'group' field in the annotation we will
    just overwrite it!

    """
    def is_reply(annotation):
        """Return True if this annotation is a reply."""
        if annotation.get('references'):
            return True
        else:
            return False

    if not is_reply(annotation):
        return

    # Get the top-level annotation that this annotation is a reply
    # (or a reply-to-a-reply etc) to.
    top_level_annotation_id = annotation['references'][0]
    top_level_annotation = models.Annotation.fetch(top_level_annotation_id)

    # If we can't find the top-level annotation, there's nothing we can do, and
    # we should bail.
    if top_level_annotation is None:
        return

    if 'group' in top_level_annotation:
        annotation['group'] = top_level_annotation['group']
        annotation['group2'] = top_level_annotation['group']
        annotation['language'] = top_level_annotation['language']
    else:
        if 'group' in annotation:
            del annotation['group']

#annotran's version of h.api.schemas.schema
schema = {
    'type': 'object',
    'properties': {
        'document': {
            'type': 'object',
            'properties': {
                'link': {
                    'type': 'array',
                },
            },
        },
        'permissions': {
            'title': 'Permissions',
            'description': 'Annotation action access control list',
            'type': 'object',
            'patternProperties': {
                '^(admin|delete|read|update)$': {
                    'type': 'array',
                    'items': {
                        'type': 'string',
                        'pattern': '^(acct:|group:|group2:|language:).+$',
                    },
                }
            },
        },
    },
}

#annotran's version of h.api.search
ANNOTATION_MAPPING = {
    '_id': {'path': 'id'},
    '_source': {'excludes': ['id']},
    'analyzer': 'keyword',
    'properties': {
        'annotator_schema_version': {'type': 'string'},
        'created': {'type': 'date'},
        'updated': {'type': 'date'},
        'quote': {'type': 'string', 'analyzer': 'uni_normalizer'},
        'tags': {'type': 'string', 'analyzer': 'uni_normalizer'},
        'text': {'type': 'string', 'analyzer': 'uni_normalizer'},
        'deleted': {'type': 'boolean'},
        'uri': {
            'type': 'string',
            'index_analyzer': 'uri',
            'search_analyzer': 'uri',
            'fields': {
                'parts': {
                    'type': 'string',
                    'index_analyzer': 'uri_parts',
                    'search_analyzer': 'uri_parts',
                },
            },
        },
        'user': {'type': 'string', 'index': 'analyzed', 'analyzer': 'user'},
        'target': {
            'properties': {
                'source': {
                    'type': 'string',
                    'index_analyzer': 'uri',
                    'search_analyzer': 'uri',
                    'copy_to': ['uri'],
                },
                # We store the 'scope' unanalyzed and only do term filters
                # against this field.
                'scope': {
                    'type': 'string',
                    'index': 'not_analyzed',
                },
                'selector': {
                    'properties': {
                        'type': {'type': 'string', 'index': 'no'},

                        # Annotator XPath+offset selector
                        'startContainer': {'type': 'string', 'index': 'no'},
                        'startOffset': {'type': 'long', 'index': 'no'},
                        'endContainer': {'type': 'string', 'index': 'no'},
                        'endOffset': {'type': 'long', 'index': 'no'},

                        # Open Annotation TextQuoteSelector
                        'exact': {
                            'path': 'just_name',
                            'type': 'string',
                            'fields': {
                                'quote': {
                                    'type': 'string',
                                    'analyzer': 'uni_normalizer',
                                },
                            },
                        },
                        'prefix': {'type': 'string'},
                        'suffix': {'type': 'string'},

                        # Open Annotation (Data|Text)PositionSelector
                        'start': {'type': 'long'},
                        'end':   {'type': 'long'},
                    }
                }
            }
        },
        'permissions': {
            'index_name': 'permission',
            'properties': {
                'read': {'type': 'string'},
                'update': {'type': 'string'},
                'delete': {'type': 'string'},
                'admin': {'type': 'string'}
            }
        },
        'references': {'type': 'string'},
        'document': {
            'enabled': False,  # indexed explicitly by the save function
        },
        'thread': {
            'type': 'string',
            'analyzer': 'thread'
        },
        'group': {
            'type': 'string',
        },
        'group2': {
            'type': 'string',
        },
        'language': {
            'type': 'string',
        }

    }
}