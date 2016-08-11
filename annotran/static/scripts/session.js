/*

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
**/

//this is session service entirely duplicated from h, and extended with language
//TODO: get rid of unnecessary duplicated code if possible!

'use strict';

var assign = require('core-js/library/fn/object/assign');
var angular = require('angular');

var eventsa = require('./events')
var events = require('../../../../h/h/static/scripts//events.js');
var retryUtil = require('../../../../h/h/static/scripts//retry-util');

var CACHE_TTL = 5 * 60 * 1000; // 5 minutes
//var CACHE_TTL = 1; // 0 minutes

function sessionActions(options) {
  var actions = {
    login: {
      method: 'POST',
      params: { __formid__: 'login' },
    },

    logout: {
      method: 'POST',
      params: { __formid__: 'logout' },
    },

    _load: { method: 'GET' },

    dismiss_sidebar_tutorial: {
      method: 'POST',
      params: { path: 'dismiss_sidebar_tutorial' },
    }
  };

  Object.keys(actions).forEach(function (action) {
    assign(actions[action], options);
  });

  return actions;
}


/**
 * @ngdoc service
 * @name session
 * @description
 * Access to the application session and account actions. This service gives
 * other parts of the application access to parts of the server-side session
 * state (such as current authenticated userid, CSRF token, etc.).
 *
 * In addition, this service also provides helper methods for mutating the
 * session state, by, e.g. logging in, logging out, etc.
 *
 * @ngInject
 */
function session($http, $resource, $rootScope, flash, raven, settings) {
  // Headers sent by every request made by the session service.
  var headers = {};
  var actions = sessionActions({
    headers: headers,
    transformResponse: process,
    withCredentials: true
  });
  var endpoint = new URL('/app/:path', settings.serviceUrl).href;
  var resource = $resource(endpoint, {}, actions);

  // Blank initial model state
  resource.state = {};

  // Cache the result of _load()
  var lastLoad;
  var lastLoadTime;

  /**
   * @name session.load()
   * @description Fetches the session data from the server.
   * @returns A promise for the session data.
   *
   * The data is cached for CACHE_TTL across all actions of the session
   * service: that is, a call to login() will update the session data and a call
   * within CACHE_TTL milliseconds to load() will return that data rather than
   * triggering a new request.
   */
  resource.load = function () {
    if (!lastLoadTime || (Date.now() - lastLoadTime) > CACHE_TTL) {

      // The load attempt is automatically retried with a backoff.
      //
      // This serves to make loading the app in the extension cope better with
      // flakey connectivity but it also throttles the frequency of calls to
      // the /app endpoint.
      lastLoadTime = Date.now();
      lastLoad = retryUtil.retryPromiseOperation(function () {
        return resource._load().$promise;
      }).then(function (session) {
        lastLoadTime = Date.now();
        return session;
      }).catch(function (err) {
        lastLoadTime = null;
        throw err;
      });
    }

    return lastLoad;
  }

  resource.reload = function (language_name) {
      lastLoad = retryUtil.retryPromiseOperation(function () {
        return resource._load().$promise;
      }).then(function (session) {
        lastLoadTime = Date.now();
        $rootScope.$broadcast(eventsa.SESSION_RELOADED)
        return session;
      }).catch(function (err) {
        lastLoadTime = null;
        throw err;
      });

  }

  /**
   * @name session.update()
   *
   * @description Update the session state using the provided data.
   *              This is a counterpart to load(). Whereas load() makes
   *              a call to the server and then updates itself from
   *              the response, update() can be used to update the client
   *              when new state has been pushed to it by the server.
   */
  resource.update = function (model) {
    var isInitialLoad = !resource.state.csrf;

    var userChanged = model.userid !== resource.state.userid;
    var groupsChanged = !angular.equals(model.groups, resource.state.groups);
    var languagesChanged = !angular.equals(model.languages, resource.state.languages);

    // Copy the model data (including the CSRF token) into `resource.state`.
    angular.copy(model, resource.state);

    // Set up subsequent requests to send the CSRF token in the headers.
    if (resource.state.csrf) {
      headers[$http.defaults.xsrfHeaderName] = resource.state.csrf;
    }

    lastLoad = Promise.resolve(resource.state);
    lastLoadTime = Date.now();

    $rootScope.$broadcast(events.SESSION_CHANGED, {
      initialLoad: isInitialLoad,
    });

    if (userChanged) {
      $rootScope.$broadcast(events.USER_CHANGED, {
        initialLoad: isInitialLoad,
      });

      // associate error reports with the current user in Sentry
      if (resource.state.userid) {
        raven.setUserInfo({
          id: resource.state.userid,
        })
      } else {
        raven.setUserInfo(undefined);
      }
    }

    if (groupsChanged) {
      $rootScope.$broadcast(events.GROUPS_CHANGED, {
        initialLoad: isInitialLoad,
      });
    }

    if (languagesChanged) {
      $rootScope.$broadcast(eventsa.LANGUAGES_CHANGED, {
        initialLoad: isInitialLoad,
        languages: model,
      });
    }

    // Return the model
    return model;
  };

  function process(data, headersGetter) {
    // Parse as json
    data = angular.fromJson(data);

    // Lift response data
    var model = data.model || {};
    if (typeof data.errors !== 'undefined') {
      model.errors = data.errors;
    }
    if (typeof data.reason !== 'undefined') {
      model.reason = data.reason;
    }

    // Fire flash messages.
    for (var type in data.flash) {
      if (data.flash.hasOwnProperty(type)) {
        var msgs = data.flash[type];
        for (var i = 0, len = msgs.length; i < len; i++) {
          flash[type](msgs[i]);
        }
      }
    }
    
    return resource.update(model);
  }

  return resource;
}

module.exports = session;
