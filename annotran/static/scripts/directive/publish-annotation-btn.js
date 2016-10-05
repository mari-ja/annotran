'use strict';

var eventsa =  require('../events');

/**
 * @ngdoc directive
 * @name publishAnnotationBtn
 * @description Displays a combined privacy/selection post button to post
 *              a new annotation
 */
// @ngInject
module.exports = function (crossframe, $rootScope) {
  return {
    bindToController: true,
    controller: function () {
      this.showDropdown = false;
      this.privateLabel = 'Only Me';

      $rootScope.$on('moving_to_sentence', function () {
        console.log($rootScope.sentencebysentence);
        if($rootScope.sentencebysentence == "on") {
          console.log("MOVING TO SENTENCE");

        }
      });

      this.publishDestination = function () {
        return this.isShared ? this.group.name : this.privateLabel;
      }

      this.moveToNext = function() {
          crossframe.call("moveToNextSentence");
      }

      this.groupType = function () {
        return this.group.public ? 'public' : 'group';
      }

      this.setPrivacy = function (level) {
        this.onSetPrivacy({level: level});
      }
    },
    controllerAs: 'vm',
    restrict: 'E',
    scope: {
      group: '=',
      canPost: '=',
      isShared: '=',
      onCancel: '&',
      onSave: '&',
      onSetPrivacy: '&'
    },
    templateUrl: 'publish_annotation_btn.html'
  };
}