require('pkginfo')(module)
version = @version

_ = require('underscore')
fs = require('fs')
request = require('request')
needle = require('needle');

class Client
  MAX_RETRIES = 5

  constructor: (company, product, options = {}, defaultOptions = {}, extraOptionsList = []) ->
    coreDefaultOptions =
      user_agent: @version()

    @env = options.env
    @env ||= process.env[company.toUpperCase() + '_' + product.toUpperCase() + '_ENV'] || process.env[product.toUpperCase() + '_ENV']

    @optionsList = ['scheme', 'host', 'port', 'user_agent'].concat(extraOptionsList)

    @options = {}

    @loadFromHash('params', options)

    @loadFromConfig(company, product, options.config)

    @loadFromConfig(company, product, process.env[company.toUpperCase() + '_' + product.toUpperCase() + '_CONFIG'])
    @loadFromConfig(company, product, process.env[company.toUpperCase() + '_CONFIG'])

    @loadFromEnv(company.toUpperCase() + '_' + product.toUpperCase())
    @loadFromEnv(company.toUpperCase())

    suffixes = []

    if @env?
      suffixes.push("-#{@env}")
      suffixes.push("_#{@env}")

    suffixes.push('')

    for suffix in suffixes
      for ext in ['.json']
        for config_base in ["#{company}-#{product}", "#{company}_#{product}", company]
          @loadFromConfig(company, product, "#{config_base}#{suffix}#{ext}")
          @loadFromConfig(company, product, ".#{config_base}#{suffix}#{ext}")
          @loadFromConfig(company, product, "~/#{config_base}#{suffix}#{ext}")
          @loadFromConfig(company, product, "~/.#{config_base}#{suffix}#{ext}")

    @loadFromHash('defaults', defaultOptions)
    @loadFromHash('defaults', coreDefaultOptions)
    keys = ["server", "tenant", "username", "password"]
    keystone = @options["keystone"]
    if keystone and _.intersection(keys, _.keys(keystone).length is 4)
      @useKeystone = true

  version: ->
    "iron_core_node-#{version}"

  setOption: (source, name, value) ->
    if (not @options[name]?) and value?
      @options[name] = value

  loadFromHash: (source, hash) ->
    if hash?
      @setOption(source, option, hash[option]) for option in @optionsList

  loadFromEnv: (prefix) ->
    @setOption('environment variable', option,
      process.env[prefix + '_' + option.toUpperCase()]) for option in @optionsList

  getSubHash: (hash, subs) ->
    return null unless hash?

    for sub in subs
      return null unless hash[sub]?

      hash = hash[sub]

    hash

  loadFromConfig: (company, product, configFile) ->
    if configFile?
      realConfigFile = configFile.replace(/^~/, process.env.HOME)

      configData = '{}'

      try
        configData = fs.readFileSync(realConfigFile)

      config = JSON.parse(configData)

      if @env?
        @loadFromHash(configFile, @getSubHash(config, [@env, "#{company}_#{product}"]))
        @loadFromHash(configFile, @getSubHash(config, [@env, company, product]))
        @loadFromHash(configFile, @getSubHash(config, [@env, product]))
        @loadFromHash(configFile, @getSubHash(config, [@env, company]))

        @loadFromHash(configFile, @getSubHash(config, ["#{company}_#{product}", @env]))
        @loadFromHash(configFile, @getSubHash(config, [company, product, @env]))
        @loadFromHash(configFile, @getSubHash(config, [product, @env]))
        @loadFromHash(configFile, @getSubHash(config, [company, @env]))

        @loadFromHash(configFile, @getSubHash(config, [@env]))

      @loadFromHash(configFile, @getSubHash(config, ["#{company}_#{product}"]))
      @loadFromHash(configFile, @getSubHash(config, [company, product]))
      @loadFromHash(configFile, @getSubHash(config, [product]))
      @loadFromHash(configFile, @getSubHash(config, [company]))
      @loadFromHash(configFile, @getSubHash(config, []))

  headers: ->
    {'User-Agent': @options.user_agent}

  url: ->
    "#{@options.scheme}://#{@options.host}:#{@options.port}/"

  request: (requestInfo, cb, retry = 0) ->
    requestBind = _.bind(@request, @)

    request(requestInfo, (error, response, body) ->
      if error && not response
        cb(error, response, body)
      else if response.statusCode == 200
        cb(error, response, body)
      else
        if response.statusCode == 503 and retry < @MAX_RETRIES
          delay = Math.pow(4, retry) * 100 * Math.random()
          _.delay(requestBind, delay, requestInfo, cb, retry + 1)
        else
          cb(error, response, body)
    )

  requestWrapper: (url, method, params, cb) ->
    self = this
    @getToken (token) ->
      headers = _.extend(self.headers(),
        Authorization: "OAuth " + token
      )
      requestInfo =
        method: method
        uri: self.url() + url
        headers: headers
        json: params

      self.request(requestInfo, cb)

  get: (method, params, cb) ->
    @requestWrapper(method, "GET", params, cb)

  post: (method, params, cb) ->
    @requestWrapper(method, "POST", params, cb)

  put: (method, params, cb) ->
    @requestWrapper(method, "PUT", params, cb)

  delete: (method, params, cb) ->
    @requestWrapper(method, "DELETE", params, cb)

  patch: (method, params, cb) ->
    @requestWrapper(method, "PATCH", params, cb)

  parseResponse: (error, response, body, cb, parseJson = true) ->
    if error
      cb(error, null)
    else if response.statusCode == 200
      body = JSON.parse(body) if parseJson and typeof(body) == 'string'

      cb(null, body)
    else
      if body instanceof String or typeof(body) == 'string'
        cb(new Error(body), null)
      else if body and body.msg
        cb(new Error(body.msg), null)
      else
        cb(new Error('Unknown error'), null)


  Date::add = (mseconds) ->
    @setTime @getTime() + (mseconds)
    this

  getToken: (cb) ->
    return cb(@options.token)  unless @useKeystone
    currentDate = new Date()
    if not @token? or currentDate > @expires
      uri = @options["keystone"]["server"] + "tokens"
      body =
        tenantName: @options["keystone"]["tenant"]
        passwordCredentials:
          username: @options["keystone"]["username"]
          password: @options["keystone"]["password"]

      self = this
      return needle.post(uri, {auth: body}, {json: true}, (err, resp) ->
          if not err and resp.statusCode is 200
            token = resp.body["access"]["token"]
            timespan = Math.abs(new Date(token["expires"]) - new Date(token["issued_at"]))
            self.expires = currentDate.add(Math.round(timespan))
            self.token = token["id"]
          cb(self.token)
      )
    cb(@token)

module.exports.Client = Client
