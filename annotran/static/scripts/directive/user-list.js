'use strict';
var persona = require('../../../../../h/h/static/scripts/filter/persona.js')

// @ngInject
function Controller($scope, flash, session, formRespond, settings, auth, languages, groups) {

  this.serviceUrl = settings.serviceUrl;


  if ($scope.model == null) {
    $scope.model = {};
  }

  $scope.hideUserList = function () {
    $scope.$parent.userList.visible = false;
  };

  $scope.setUser = function (id) {
    this.$root.selectedUser = id;

    if (this.$root.selectedUser == "self"){
      this.$root.selectedUser = this.$root.currentUser;
    }

    this.userList();
  };

  $scope.userList = function () {
    return $scope.$root.updateUserList()
  };

  // for some reason we have to use an array here as NG repeat won't handle it properly otherwise
  $scope.list_of_users = $scope.$root.list_of_users;
  $scope.$root.updateUserList();
  
}

module.exports = {
  directive: function () {
    return {
      bindToController: true,
      controller: Controller,
      controllerAs: 'userListController',
      restrict: 'E',
      scope: {
        auth: '=',
        session: '=',
        languages: '=',
        groups: '=',
        onClose: '&',
        showUserList: '='
      },
      templateUrl: 'user_list.html',
    };
  },
  Controller: Controller,
};
