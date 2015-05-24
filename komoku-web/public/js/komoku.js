var komokuApp = angular.module('komokuApp', []);


komokuApp.controller('KomokuCtrl', function ($scope, $http) {

  Graphs = {}
  GraphsData = {}

  $scope.selectKey = function(key) {
    $scope.selectedKey = key
    $http.get('last.json', {params: {key: key}}).success(function(data) {
      $scope.lastPoints = data;
    });
    $http.get('graphs.json', {params: {key: key}}).success(function(data) {
      angular.forEach(data, function(data, key) {
        if (data.length > 0) {
          ddata = []
          xdata = ['x']
          ydata = ['data']
          angular.forEach(data, function(value) {
            xdata.push(value[0]*1000)
            ydata.push(value[1]) 
          })
          Graphs[key].load({columns: [xdata, ydata]})
        } else {} // TODO display no data msg
      })
    });
  }

  // prepare graps
  graphsTimespans = {
    'last_hour': {seconds: 3600*1000, format: '%H:%M'},
    'last_24h': {seconds: 3600*24*1000, format: '%H:%M'},
    'last_month': {seconds: 31*3600*24*1000, format: '%Y-%m-%d'},
  }

  angular.forEach(graphsTimespans, function(value, key) {
    Graphs[key] = c3.generate({
      bindto: "#graph_"+key,
      data: {
        empty: {
          label: {
            text: "No Data"
          }
        },
        x: 'x',
        columns: [
          ['x', 0]
          ['data', 0]
        ]
      },
      axis: {
        x: {
          type: 'timeseries',
          tick: {
            format: value.format,
            culling: {
              max: 5
            }
          }
        }
      }
    });
  })

  // Fetch keys list
  $http.get('keys.json').success(function(data) {
    $scope.keys = data;
  });

  console.log("about to subscribe")
  // Subscribe to key changes
  source = new EventSource('/subscribe');
  source.addEventListener('message', function (event) {
    data = JSON.parse(event.data)
    console.log(data)
    $scope.keys[data.key].value = data.value
    if ($scope.selectedKey == data.key) {
      $scope.lastPoints.push([new Date(), data.value])

      // update charts
      angular.forEach(graphsTimespans, function(opts, key) {
        // TODO replace last point if prev time < step
        Graphs[key].flow({
          columns: [
            ['x', new Date()],
            ['data', data.value]
          ]
        })
      })
    }
    $scope.$apply()
  }, false);


});
