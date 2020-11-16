# Since we are using the non-standard version of OpenStudio standards, we must call the require explicitly here.
require 'openstudio-standards'

class AmbientLoopPrototypeBuildingByLocation < OpenStudio::Measure::ModelMeasure

  Dir[File.dirname(__FILE__) + '/resources/*.rb'].each { |file| require file }

  # resource file modules
  include OsLib_HelperMethods

  # define the name that a user will see, this method may be deprecated as the display name in PAT comes from
  # the name field in measure.xml
  def name
    return "Ambient Loop Prototype Building By Location"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # make a choice argument for the building type
    building_type_chs = OpenStudio::StringVector.new
    building_type_chs << 'SecondarySchool'
    building_type_chs << 'PrimarySchool'
    building_type_chs << 'SmallOffice'
    building_type_chs << 'MediumOffice'
    building_type_chs << 'LargeOffice'
    building_type_chs << 'SmallHotel'
    building_type_chs << 'LargeHotel'
    building_type_chs << 'Warehouse'
    building_type_chs << 'RetailStandalone'
    building_type_chs << 'RetailStripmall'
    building_type_chs << 'QuickServiceRestaurant'
    building_type_chs << 'FullServiceRestaurant'
    building_type_chs << 'MidriseApartment'
    building_type_chs << 'HighriseApartment'
    building_type_chs << 'Hospital'
    building_type_chs << 'Outpatient'
    building_type = OpenStudio::Measure::OSArgument.makeChoiceArgument('building_type', building_type_chs, true)
    building_type.setDisplayName('Building Type')
    building_type.setDefaultValue('SmallOffice')
    args << building_type

    # make a choice argument for the template
    template_chs = OpenStudio::StringVector.new
    template_chs << 'DOE Ref Pre-1980'
    template_chs << 'DOE Ref 1980-2004'
    template_chs << '90.1-2004'
    template_chs << '90.1-2007'
    # template_chs << '189.1-2009'
    template_chs << '90.1-2010'
    template_chs << '90.1-2013'
    template_chs << 'NECB 2011'
    template = OpenStudio::Measure::OSArgument.makeChoiceArgument('template', template_chs, true)
    template.setDisplayName('Template')
    template.setDefaultValue('90.1-2010')
    args << template

    weather_file_name = OpenStudio::Measure::OSArgument.makeStringArgument('weather_file_name', true)
    weather_file_name.setDisplayName('Weather File Name')
    weather_file_name.setDescription('Name of the weather file. This is the filename with the extension (e.g. NewWeather.epw). Optionally this can include the full file path, but for most use cases should just be file name.')
    args << weather_file_name

    args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # assign the user inputs to variables
    args = OsLib_HelperMethods.createRunVariables(runner, model, user_arguments, arguments(model))
    if !args then return false end

    # assign the user inputs to variables that can be accessed across the measure
    building_type = args['building_type']
    template = args['template']

    # find weather file
    osw_file = runner.workflow.findFile(args['weather_file_name'])
    if osw_file.is_initialized
      weather_file = osw_file.get.to_s
    else
      runner.registerError("Did not find #{args['weather_file_name']} in paths described in OSW file.")
      return false
    end

    # load EPW file
    epw_file = OpenStudio::Weather::Epw.load(weather_file)

    # load the STAT file
    stat_file = "#{File.join(File.dirname(epw_file.filename), '..', 'lib', 'weather', File.basename(epw_file.filename, '.*'))}.stat"
    unless File.exist? stat_file
      runner.registerInfo 'Could not find STAT file by filename, looking in the directory'
      stat_files = Dir["#{File.dirname(epw_file.filename)}/*.stat"]
      if stat_files.size > 1
        runner.registerError('More than one stat file in the EPW directory')
        return false
      end
      if stat_files.empty?
        runner.registerError('Cound not find the stat file in the EPW directory')
        return false
      end
      runner.registerInfo "Using STAT file: #{stat_files.first}"
      stat_file = stat_files.first
    end
    unless stat_file
      runner.registerError 'Could not find stat file'
      return false
    end
    stat_model = EnergyPlus::StatFile.new(stat_file)

    # get climate zone from stat file
      text = nil
      File.open(stat_file) do |f|
        text = f.read.force_encoding('iso-8859-1')
      end
      # - Climate type "3B" (ASHRAE Standard 196-2006 Climate Zone)**
      # - Climate type "6A" (ASHRAE Standards 90.1-2004 and 90.2-2004 Climate Zone)**
      regex = /Climate type \"(.*?)\" \(ASHRAE Standards?(.*)\)\*\*/
      match_data = text.match(regex)
      if match_data.nil?
        runner.registerWarning("Can't find ASHRAE climate zone in stat file.")
      else
        climate_zone = match_data[1].to_s.strip
      end

    # assign climate zone variable to create ambient loop prototype building
    climate_zone_prototype = 'ASHRAE 169-2006-'
    climate_zone_prototype << climate_zone

    # path is relative to the run directory
    run_dir = File.join('models')
    FileUtils.mkdir_p run_dir unless Dir.exist? run_dir
    runner.registerInfo "Found run dir to be #{run_dir}"

    new_model = OpenStudio::Model::Model.new
    new_model.create_prototype_building(building_type, template, climate_zone_prototype, args['weather_file_name'])

    # for some reason new_model.save does not work inside the measure.
    File.open("#{run_dir}/prototype.osm", 'w') {|f| f << new_model.to_s}

    # remove existing objects from model
    handles = OpenStudio::UUIDVector.new
    model.objects.each do |obj|
      handles << obj.handle
    end
    model.removeObjects(handles)
    model.addObjects(new_model.toIdfFile.objects)

    # model change timestep to only one hour
    timestep = model.getTimestep
    timestep.setNumberOfTimestepsPerHour(1)

    # echo the new space's name back to the user
    runner.registerInfo("Model replaced.")

    # report final condition of model
    runner.registerFinalCondition("AmbientLoopSmallOffice Ran")

    # add weather data
    weather_file = model.getWeatherFile
    weather_file.setCity(epw_file.city)
    weather_file.setStateProvinceRegion(epw_file.state)
    weather_file.setCountry(epw_file.country)
    weather_file.setDataSource(epw_file.data_type)
    weather_file.setWMONumber(epw_file.wmo.to_s)
    weather_file.setLatitude(epw_file.lat)
    weather_file.setLongitude(epw_file.lon)
    weather_file.setTimeZone(epw_file.gmt)
    weather_file.setElevation(epw_file.elevation)
    weather_file.setString(10, "file:///#{epw_file.filename}")

    weather_name = "#{epw_file.city}_#{epw_file.state}_#{epw_file.country}"
    weather_lat = epw_file.lat
    weather_lon = epw_file.lon
    weather_time = epw_file.gmt
    weather_elev = epw_file.elevation

    # add site data
    site = model.getSite
    site.setName(weather_name)
    site.setLatitude(weather_lat)
    site.setLongitude(weather_lon)
    site.setTimeZone(weather_time)
    site.setElevation(weather_elev)

    runner.registerInfo("city is #{epw_file.city}. State is #{epw_file.state}")

    # add SiteWaterMainsTemperature
    water_temp = model.getSiteWaterMainsTemperature
    water_temp.setAnnualAverageOutdoorAirTemperature(stat_model.mean_dry_bulb)
    water_temp.setMaximumDifferenceInMonthlyAverageOutdoorAirTemperatures(stat_model.delta_dry_bulb)
    runner.registerInfo("mean dry bulb is #{stat_model.mean_dry_bulb}")

    # remove all the DesignDay objects that are in the file
    model.getObjectsByType('OS:SizingPeriod:DesignDay'.to_IddObjectType).each(&:remove)

    # find the ddy files
    ddy_file = "#{File.join(File.dirname(epw_file.filename), '..', 'lib', 'weather', File.basename(epw_file.filename, '.*'))}.ddy"
    unless File.exist? ddy_file
      ddy_files = Dir["#{File.dirname(epw_file.filename)}/*.ddy"]
      if ddy_files.size > 1
        runner.registerError('More than one ddy file in the EPW directory')
        return false
      end

      if ddy_files.empty?
        runner.registerError('could not find the ddy file in the EPW directory')
        return false
      end

      ddy_file = ddy_files.first
    end

    unless ddy_file
      runner.registerError "Could not find DDY file for #{ddy_file}"
      return error
    end

    ddy_model = OpenStudio::EnergyPlus.loadAndTranslateIdf(ddy_file).get
    ddy_model.getObjectsByType('OS:SizingPeriod:DesignDay'.to_IddObjectType).each do |d|
      # grab only the ones that matter
      ddy_list = /(Htg 99.6. Condns DB)|(Clg .4. Condns WB=>MDB)|(Clg .4% Condns DB=>MWB)/
      if d.name.get =~ ddy_list
        runner.registerInfo("Adding object #{d.name}")

        # add the object to the existing model
        model.addObject(d.clone)
      end
    end

    # set climate zone
    climateZones = model.getClimateZones
    climateZones.clear
    climateZones.setClimateZone('ASHRAE', climate_zone)
    runner.registerInfo("Setting Climate Zone to #{climateZones.getClimateZones('ASHRAE').first.value}")

    # add final condition
    runner.registerFinalCondition("The final weather file is #{model.getWeatherFile.city} and the model has #{model.getDesignDays.size} design day objects.")
    true
  end
end

# this allows the measure to be use by the application
AmbientLoopPrototypeBuildingByLocation.new.registerWithApplication
