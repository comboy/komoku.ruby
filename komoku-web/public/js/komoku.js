var komokuApp = angular.module('komokuApp', []);


komokuApp.controller('KomokuCtrl', function ($scope, $http) {

  dyGraphs = {}
  dyGraphsData = {}

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
          dyGraphsData[key] = ddata
          dyGraphs[key].updateOptions({'file': ddata})
        } else {} // TODO display no data msg
      })
    });
  }

  // Fetch keys list
  $http.get('keys.json').success(function(data) {
    $scope.keys = data;
  });

  // Subscribe to key changes
  source = new EventSource('/subscribe');
  source.addEventListener('message', function (event) {
    data = JSON.parse(event.data)
    console.log(data)
    $scope.keys[data.key].value = data.value
    if ($scope.selectedKey == data.key) {
      $scope.lastPoints.push([new Date(), data.value])
      angular.forEach(dyGraphsData, function(points, key) {
        points.push([new Date(), data.value])
        dyGraphs[key].updateOptions({'file': points})
      })
      // TODO also updates charts and stuff
    }
    $scope.$apply()
  }, false);

  // prepare graps
  graphsTimespans = {
    'last_hour': new Date(new Date() - 3600*1000),
    'last_24h': new Date(new Date() - 3600*24*1000),
    'last_month': new Date(new Date() - 31*3600*24*1000),
  }

  angular.forEach(graphsTimespans, function(value, key) {
    dyGraphs[key] = new Dygraph(document.getElementById("dygraph_"+key), [],
    {
      dateWindow: [value, new Date()],
      labels: ['Time', 'Value']
    });
  })


});
