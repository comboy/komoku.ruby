var komokuApp = angular.module('komokuApp', []);

komokuApp.controller('KomokuCtrl', function ($scope, $http) {

  $scope.selectKey = function(key) {
    $scope.selectedKey = key
    $http.get('last.json', {params: {key: key}}).success(function(data) {
      $scope.lastPoints = data;
    });
  }

  $http.get('keys.json').success(function(data) {
    $scope.keys = data;
  });
});
