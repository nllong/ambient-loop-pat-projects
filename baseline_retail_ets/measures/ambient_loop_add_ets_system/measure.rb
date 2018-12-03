class AmbientLoopAddEtsSystem < OpenStudio::Measure::ModelMeasure
  def name
    return "Ambient Loop Add ETS System"
  end

  def description
    return "Apply an ETS system to a model"
  end

  def modeler_description
    return "This measure removes the existing HVAC system and replaces it with an energy transfer station."
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Measure::OSArgumentVector.new

    return args
  end

  # Return the list of thermal zones that will have an ETS (exclude attics)
  def get_thermal_zones(model)
    zones = []
    model.getThermalZones.each do |thermal_zone|
      add_zone = true
      thermal_zone.spaces.each do |space|
        next unless space.spaceType.is_initialized
        next unless space.spaceType.get.standardsSpaceType.is_initialized

        if space.spaceType.get.standardsSpaceType.get == 'Attic'
          add_zone = false
        end
      end
      zones << thermal_zone if add_zone
    end

    return zones
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # Use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # path is relative to the run directory
    run_dir = File.join('models')
    FileUtils.mkdir_p run_dir unless Dir.exist? run_dir

    runner.registerInfo "trying to remove HVAC equipment"
    model.remove_prm_hvac

    File.open("#{run_dir}/prototype-no-hvac.osm", 'w') {|f| f << model.to_s}

    # add in the ambient loop model -- this is definitely not right. This adds a water to air heat pump
    model.add_energy_transfer_station("Water-to-Air Heat Pump", get_thermal_zones(model))

    File.open("#{run_dir}/final.osm", 'w') {|f| f << model.to_s}

    return true
  end
end

# register the measure to be used by the application
AmbientLoopAddEtsSystem.new.registerWithApplication
