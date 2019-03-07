require 'openstudio'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'

require_relative '../measure.rb'

require 'fileutils'

class AmbientLoopReports_Test < MiniTest::Unit::TestCase
  def is_openstudio_2?
    begin
      workflow = OpenStudio::WorkflowJSON.new
    rescue StandardError
      return false
    end
    true
  end

  def model_in_path_default
    "#{File.dirname(__FILE__)}/example_model.osm"
  end

  def epw_path_default
    # make sure we have a weather data location
    epw = nil
    epw = OpenStudio::Path.new(File.expand_path("#{File.dirname(__FILE__)}/USA_CO_Golden-NREL.724666_TMY3.epw"))
    assert(File.exist?(epw.to_s))
    epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    "#{File.dirname(__FILE__)}/output/#{test_name}"
  end

  def model_out_path(test_name)
    "#{run_dir(test_name)}/example_model.osm"
  end

  def sql_path(test_name)
    if is_openstudio_2?
      "#{run_dir(test_name)}/run/eplusout.sql"
    else
      "#{run_dir(test_name)}/ModelToIdf/EnergyPlusPreProcess-0/EnergyPlus-0/eplusout.sql"
    end
  end

  def report_path(test_name)
    "#{run_dir(test_name)}/report.html"
  end

  # method for running the test simulation using OpenStudio 1.x API
  def setup_test_1(test_name, epw_path)
    co = OpenStudio::Runmanager::ConfigOptions.new(true)
    co.findTools(false, true, false, true)

    unless File.exist?(sql_path(test_name))
      puts 'Running EnergyPlus'

      wf = OpenStudio::Runmanager::Workflow.new('modeltoidf->energypluspreprocess->energyplus')
      wf.add(co.getTools)
      job = wf.create(OpenStudio::Path.new(run_dir(test_name)), OpenStudio::Path.new(model_out_path(test_name)), OpenStudio::Path.new(epw_path))

      rm = OpenStudio::Runmanager::RunManager.new
      rm.enqueue(job, true)
      rm.waitForFinished
    end
  end

  # method for running the test simulation using OpenStudio 2.x API
  def setup_test_2(test_name, epw_path)
    osw_path = File.join(run_dir(test_name), 'in.osw')
    osw_path = File.absolute_path(osw_path)

    workflow = OpenStudio::WorkflowJSON.new
    workflow.setSeedFile(File.absolute_path(model_out_path(test_name)))
    workflow.setWeatherFile(File.absolute_path(epw_path))
    workflow.saveAs(osw_path)

    cli_path = OpenStudio.getOpenStudioCLI
    cmd = "\"#{cli_path}\" run -w \"#{osw_path}\""
    puts cmd
    system(cmd)
  end

  # create test files if they do not exist when the test first runs
  def setup_test(test_name, idf_output_requests, model_in_path = model_in_path_default, epw_path = epw_path_default)
    FileUtils.mkdir_p(run_dir(test_name)) unless File.exist?(run_dir(test_name))
    assert(File.exist?(run_dir(test_name)))

    FileUtils.rm(report_path(test_name)) if File.exist?(report_path(test_name))

    assert(File.exist?(model_in_path))

    if File.exist?(model_out_path(test_name))
      FileUtils.rm(model_out_path(test_name))
    end

    # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf
    workspace = OpenStudio::Workspace.new('Draft'.to_StrictnessLevel, 'EnergyPlus'.to_IddFileType)
    workspace.addObjects(idf_output_requests)
    rt = OpenStudio::EnergyPlus::ReverseTranslator.new
    request_model = rt.translateWorkspace(workspace)

    translator = OpenStudio::OSVersion::VersionTranslator.new
    model = translator.loadModel(model_in_path)
    assert(!model.empty?)
    model = model.get
    model.addObjects(request_model.objects)
    model.save(model_out_path(test_name), true)

    if is_openstudio_2?
      setup_test_2(test_name, epw_path)
    else
      setup_test_1(test_name, epw_path)
    end
  end

  def test_number_of_arguments_and_argument_names
    # create an instance of the measure
    measure = AmbientLoopReports.new

    # get arguments and test that they are what we are expecting
    arguments = measure.arguments()
    assert_equal(0, arguments.size)
  end

  def test_report_generation
    measure = AmbientLoopReports.new
    runner = OpenStudio::Ruleset::OSRunner.new

    arguments = measure.arguments()
    argument_map = OpenStudio::Ruleset.convertOSArgumentVectorToMap(arguments)

    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)

    # mimic the process of running this measure in OS App or PAT. Optionally set custom model_in_path and custom epw_path.
    epw_path = epw_path_default

    # do not rerun the model if it already exists
    unless File.exist? model_out_path(__method__)
      setup_test(__method__, idf_output_requests)
    end

    assert(File.exist?(model_out_path(__method__)))
    assert(File.exist?(sql_path(__method__)))
    assert(File.exist?(epw_path))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(__method__)))
    runner.setLastEpwFilePath(epw_path)
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(__method__)))

    # delete the measure output if it already exists
    if File.exist?(report_path(__method__))
      FileUtils.rm(report_path(__method__))
    end
    assert(!File.exist?(report_path(__method__)))

    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(__method__))

      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal('Success', result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end

    # make sure the report file exists
    check_file = "#{run_dir(__method__)}/report_timeseries.csv"
    assert(File.exist?(check_file))
  end
end
