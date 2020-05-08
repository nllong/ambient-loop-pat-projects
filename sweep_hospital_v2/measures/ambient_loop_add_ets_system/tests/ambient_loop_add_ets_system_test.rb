require 'openstudio'
require 'openstudio/measure/ShowRunnerOutput'
require 'fileutils'

require_relative '../measure.rb'
require 'minitest/autorun'

require 'openstudio-standards'

class AmbientLoopAddEtsSystem_Test < Minitest::Test

  def test_adding_ets
    measure = AmbientLoopAddEtsSystem.new

    # create an instance of a runner
    runner = OpenStudio::Measure::OSRunner.new(OpenStudio::WorkflowJSON.new)

    # get the model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new(File.dirname(__FILE__) + "/prototype-no-hvac.osm")
    model = translator.loadModel(path)
    assert((not model.empty?))
    model = model.get

    # get arguments
    arguments = measure.arguments(model)
    argument_map = OpenStudio::Measure.convertOSArgumentVectorToMap(arguments)
    # populate argument with specified hash value if specified
    arguments.each do |arg|
      temp_arg_var = arg.clone
      if args.key?(arg.name)
        assert(temp_arg_var.setValue(args[arg.name]))
      end
      argument_map[arg.name] = temp_arg_var
    end

    zones = measure.get_thermal_zones(model)
    # verify the number of thermal zones
    assert_equal(5, zones.size)

    # run the measure
    measure.run(model, runner, argument_map)
    result = runner.result
    show_output(result)
    assert(result.value.valueName == 'Success')

    output_dir = File.join(File.dirname(__FILE__), 'output')
    FileUtils.mkdir_p(output_dir) unless Dir.exist? output_dir
    File.open(File.join(output_dir, 'prototype-with-ets.osm'), 'w') do |file|
      file << model.to_s
    end
  end
end
