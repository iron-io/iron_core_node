require('pkginfo')(module)
version = @version

_ = require('underscore')
fs = require('fs')
request = require('request')

class Client
  MAX_RETRIES = 5

  constructor: (company, product, options = {}, defaultOptions = {}, extraOptionsList = []) ->
    coreDefaultOptions =
      user_agent: @version()

    @optionsList = ['scheme', 'host', 'port', 'user_agent'].concat(extraOptionsList)

    @options = {}

    @loadFromHash('params', options)
    @loadFromConfig(company, product, options.config)
    @loadFromConfig(company, product, process.env[company.toUpperCase() + '_' + product.toUpperCase() + '_CONFIG'])
    @loadFromConfig(company, product, process.env[company.toUpperCase() + '_CONFIG'])
    @loadFromEnv(company.toUpperCase() + '_' + product.toUpperCase())
    @loadFromEnv(company.toUpperCase())
    @loadFromConfig(company, product, "./.#{company}.json")
    @loadFromConfig(company, product, "./#{company}.json")
    @loadFromConfig(company, product, "~/.#{company}.json")
    @loadFromHash('defaults', defaultOptions)
    @loadFromHash('defaults', coreDefaultOptions)

  version: ->
    "iron_core_node-#{version}"

  setOption: (source, name, value) ->
    if (not @options[name]?) and value?
      @options[name] = value

  loadFromHash: (source, hash) ->
    if hash?
      @setOption(source, option, hash[option]) for option in @optionsList

  loadFromEnv: (prefix) ->
    @setOption('environment variable', option, process.env[prefix + '_' + option.toUpperCase()]) for option in @optionsList

  loadFromConfig: (company, product, configFile) ->
    if configFile?
      try
        realConfigFile = configFile.replace(/^~/, process.env.HOME)

        config = JSON.parse(fs.readFileSync(realConfigFile))

        @loadFromHash(configFile, config["#{company}_#{product}"])
        @loadFromHash(configFile, config[company])
        @loadFromHash(configFile, config)

  headers: ->
    {'User-Agent': @options.user_agent}

  url: ->
    "#{@options.scheme}://#{@options.host}:#{@options.port}/"

  request: (requestInfo, cb, retry = 0) ->
    requestBind = _.bind(@request, @)

    request(requestInfo, (error, response, body) ->
      if response.statusCode == 200
        cb(error, response, body)
      else
        if response.statusCode == 503 and retry < @MAX_RETRIES
          delay = Math.pow(4, retry) * 100 * Math.random()
          _.delay(requestBind, delay, requestInfo, cb, retry + 1)
        else
          cb(error, response, body)
    )

  get: (method, params, cb) ->
    requestInfo =
      method: 'GET'
      uri: @url() + method
      headers: @headers()
      qs: params

    @request(requestInfo, cb)

  post: (method, params, cb) ->
    requestInfo =
      method: 'POST'
      uri: @url() + method
      headers: @headers()
      json: params

    @request(requestInfo, cb)

  put: (method, params, cb) ->
    requestInfo =
      method: 'PUT'
      uri: @url() + method
      headers: @headers()
      json: params

    @request(requestInfo, cb)

  delete: (method, params, cb) ->
    requestInfo =
      method: 'DELETE'
      uri: @url() + method
      headers: @headers()
      qs: params

    @request(requestInfo, cb)

  parseResponse: (error, response, body, cb, parseJson = true) ->
    if response.statusCode == 200
      body = JSON.parse(body) if parseJson and typeof(body) == 'string'

      cb(null, body)
    else
      cb(new Error(body), null)

module.exports.Client = Client
