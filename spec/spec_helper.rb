require 'komoku/core'
require 'fileutils'

tmp_db = "tmp/test.db"
File.unlink tmp_db if File.exists? tmp_db

FileUtils.mkdir_p "tmp"
