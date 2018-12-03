require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'

require_relative '../measure.rb'
require 'minitest/autorun'

require 'openstudio-standards'

class AmbientLoopAddEtsSystem_Test < Minitest::Test

  def test_thermal_zone_list
    measure = AmbientLoopAddEtsSystem.new

    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new(File.dirname(__FILE__) + "/prototype-no-hvac.osm")
    model = translator.loadModel(path)
    assert((not model.empty?))
    model = model.get


    zones = measure.get_thermal_zones(model)
    puts "The thermal zones are: #{zones}"

    assert_equal(5, zones.size)
  end

end
