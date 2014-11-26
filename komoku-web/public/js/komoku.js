var komokuApp = angular.module('komokuApp', []);

komokuApp.controller('KomokuCtrl', function ($scope, $http) {

  $scope.selectKey = function(key) {
    $scope.selectedKey = key
    $http.get('last.json', {params: {key: key}}).success(function(data) {
      $scope.lastPoints = data;
    });
    $http.get('graphs.json', {params: {key: key}}).success(function(data) {
      angular.forEach(data, function(data, key) {
        if (data.length > 0) {
          ddata = []
          angular.forEach(data, function(value) {
            ddata.push([
              new Date(value[0]),
              value[1]
            ])
          })
          // TODO I guess we should be updating chart data instead of creating new object each time
          startDate = {
            'last_hour': new Date(new Date() - 3600*1000),
            'last_24h': new Date(new Date() - 3600*24*1000),
            'last_month': new Date(new Date() - 31*3600*24*1000),
          }[key]
          new Dygraph(document.getElementById("dygraph_"+key), ddata,
          {
            dateWindow: [startDate, new Date()],
            labels: ['Time', $scope.selectedKey]
          });
        } else {} // TODO display no data msg
      })
    });
  }

  $http.get('keys.json').success(function(data) {
    $scope.keys = data;
  });
});
