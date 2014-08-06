# vim: set et sw=2 ts=2 sts=2 ff=unix fenc=utf8:
# Author: Binux<i@binux.me>
#         http://binux.me
# Created on 2014-08-06 21:16:15

define (require, exports, module) ->
  require '/static/har/editablelist'

  utils = require '/static/utils'

  angular.module('entry_editor', [
    'contenteditable'
  ]).controller('EntryCtrl', ($scope, $rootScope, $sce, $http) ->
    # init
    $scope.panel = 'request'

    # on edit event
    $scope.$on('edit-entry', (ev, entry) ->
      console.log entry

      $scope.entry = entry
      $scope.entry.success_asserts ?= [{re: ''+$scope.entry.response.status, from: 'status'}, ]
      $scope.entry.failed_asserts ?= []
      $scope.entry.extract_variables ?= []

      angular.element('#edit-entry').modal('show')
      $scope.alert_hide()
    )

    # on saved event
    angular.element('#edit-entry').on('hidden.bs.modal', (ev) ->
      if $scope.panel in ['preview-headers', 'preview']
        $scope.$apply ->
            $scope.panel = 'test'

            # update env from extract_variables
            env = utils.list2dict($scope.env)
            for rule in $scope.entry.extract_variables
              if ret = $scope.preview_match(rule.re)
                env[rule.name] = ret
            $scope.env = utils.dict2list(env)

      $scope.$apply ->
        $scope.preview = undefined
    )

    # alert message for test panel
    $scope.alert = (message) ->
      angular.element('.panel-test .alert').text(message).show()
    $scope.alert_hide = () ->
      angular.element('.panel-test .alert').hide()

    # sync url with query string
    $scope.$watch('entry.request.url', () ->
      if not $scope.entry?
        return
      queryString = ({name: key, value: value} for key, value of utils.url_parse($scope.entry.request.url, true).query)

      if not angular.equals(queryString, $scope.entry.request.queryString)
        $scope.entry.request.queryString = queryString
    )
    # sync query string with url
    $scope.$watch('entry.request.queryString', (() ->
      if not $scope.entry?
        return
      url = utils.url_parse($scope.entry.request.url)
      query = {}
      for each in $scope.entry.request.queryString
        query[each.name] = each.value
      query = utils.querystring_unparse_with_variables(query)
      url.search = "?#{query}" if query
      url = utils.url_unparse(url)

      if url != $scope.entry.request.url
        $scope.entry.request.url = url
    ), true)

    # sync params with text
    $scope.$watch('entry.request.postData.params', (() ->
      if not $scope.entry?.postData?
        return
      obj = {}
      for param in $scope.entry.request.postData.params
        obj[param.name] = param.value
      $scope.entry.request.postData.text = utils.querystring_unparse_with_variables(obj)
    ), true)

    # helper for delete item from array
    $scope.delete = (hashKey, array) ->
      for each, index in array
        if each.$$hashKey == hashKey
          array.splice(index, 1)
          return

    # variables template
    $scope.variables_wrapper = (string, place_holder='') ->
      string = string or place_holder
      re = /{{\s*([\w]+?)\s*}}/g
      $sce.trustAsHtml(string.replace(re, '<span class="label label-primary">$&</span>'))

    # fetch test
    $scope.do_test = () ->
      $http.post('/har/test', {
        request:
          method: $scope.entry.request.method
          url: $scope.entry.request.url
          headers: ({name: h.name, value: h.value} for h in $scope.entry.request.headers when h.checked)
          cookies: ({name: c.name, value: c.value} for c in $scope.entry.request.cookies when c.checked)
          data: $scope.entry.request.postData?.text
        rule:
          success_asserts: $scope.entry.success_asserts
          failed_asserts: $scope.entry.failed_asserts
          extract_variables: $scope.entry.extract_variables
        env:
          variables: utils.list2dict($scope.env)
          session: $scope.session
      }).
      success((data, status, headers, config) ->
        console.log 'success', data, status
        if (status != 200)
          $scope.alert(data)
          return

        $scope.preview = data.har
        $scope.preview.success = data.success
        $scope.env = utils.dict2list(data.env.variables)
        $scope.session = data.env.session
        $scope.panel = 'preview'

        if data.har.response?.content?.text?
          setTimeout((() ->
            angular.element('.panel-preview iframe').attr("src",
              "data:#{data.har.response.content.mimeType};\
              base64,#{data.har.response.content.text}")), 0)
      ).
      error((data, status, headers, config) ->
        console.log 'error', data, status, headers, config
        $scope.alert(data)
      )

      $scope.preview_match = (re, from) ->
        data = null
        if from == 'content'
          if not (content = $scope.preview.response.content).text
            return null
          if not content.decoded
            content.decoded = atob(content.text)
          data = content.decoded
        else if from == 'status'
          data = ''+$scope.preview.response.status
        else if from.indexOf('header-')
          from = from[7..]
          for header in $scope.preview.response.headers
            if header.name.toLowerCase() == from
              data = header.value

        if not data
          return null

        try
          re = new RegExp(re)
        catch error
          return null

        if m = data.match(re)
          return if m[1] then m[1] else m[0]
        return null

      ## eof
    )
