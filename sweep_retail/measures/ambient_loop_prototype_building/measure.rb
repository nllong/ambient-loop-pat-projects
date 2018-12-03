class AmbientLoopPrototypeBuilding < OpenStudio::Measure::ModelMeasure
  def name
    return "Ambient Loop Prototype Building"
  end

  def description
    return "Ambient Loop Prototype Building"
  end

  def modeler_description
    return "Ambient Loop Prototype Building"
  end

  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    # Make an argument for the building type
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
    building_type.setDisplayName('Building Type.')
    building_type.setDefaultValue('SmallOffice')
    args << building_type

    # Make an argument for the template
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
    template.setDisplayName('Template.')
    template.setDefaultValue('90.1-2010')
    args << template

    # Make an argument for the climate zone
    climate_zone_chs = OpenStudio::StringVector.new
    climate_zone_chs << 'ASHRAE 169-2006-1A'
    # climate_zone_chs << 'ASHRAE 169-2006-1B'
    climate_zone_chs << 'ASHRAE 169-2006-2A'
    climate_zone_chs << 'ASHRAE 169-2006-2B'
    climate_zone_chs << 'ASHRAE 169-2006-3A'
    climate_zone_chs << 'ASHRAE 169-2006-3B'
    climate_zone_chs << 'ASHRAE 169-2006-3C'
    climate_zone_chs << 'ASHRAE 169-2006-4A'
    climate_zone_chs << 'ASHRAE 169-2006-4B'
    climate_zone_chs << 'ASHRAE 169-2006-4C'
    climate_zone_chs << 'ASHRAE 169-2006-5A'
    climate_zone_chs << 'ASHRAE 169-2006-5B'
    # climate_zone_chs << 'ASHRAE 169-2006-5C'
    climate_zone_chs << 'ASHRAE 169-2006-6A'
    climate_zone_chs << 'ASHRAE 169-2006-6B'
    climate_zone_chs << 'ASHRAE 169-2006-7A'
    # climate_zone_chs << 'ASHRAE 169-2006-7B'
    climate_zone_chs << 'ASHRAE 169-2006-8A'
    # climate_zone_chs << 'ASHRAE 169-2006-8B'
    climate_zone_chs << 'NECB HDD Method'
    climate_zone = OpenStudio::Measure::OSArgument.makeChoiceArgument('climate_zone', climate_zone_chs, true)
    climate_zone.setDisplayName('Climate Zone.')
    climate_zone.setDefaultValue('ASHRAE 169-2006-2A')
    args << climate_zone

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # Assign the user inputs to variables that can be accessed across the measure
    building_type = runner.getStringArgumentValue('building_type', user_arguments)
    template = runner.getStringArgumentValue('template', user_arguments)
    climate_zone = runner.getStringArgumentValue('climate_zone', user_arguments)


    # path is relative to the run directory
    run_dir = File.join('models')
    FileUtils.mkdir_p run_dir unless Dir.exist? run_dir
    runner.registerInfo "Found run dir to be #{run_dir}"

    new_model = OpenStudio::Model::Model.new
    new_model.create_prototype_building(building_type, template, climate_zone, 'USA_CO_Golden-NREL.724666_TMY3.epw')

    # For some reason new_model.save does not work inside the measure.
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

    return true
  end
end

AmbientLoopPrototypeBuilding.new.registerWithApplication
