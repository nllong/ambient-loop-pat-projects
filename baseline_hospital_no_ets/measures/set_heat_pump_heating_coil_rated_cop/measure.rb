class SetHeatPumpHeatingCoilRatedCop < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "Set Heat Pump Heating Coil Rated COP"
  end
  # human readable description
  def description
    return "Set heat pump heating coil gross rated COP."
  end
  # human readable description of modeling approach
  def modeler_description
    return "Set heat pump heating coil gross rated COP."
  end
  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    heat_cop = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("heat_cop", true)
    heat_cop.setDisplayName("Cooling Coil Rated COP")
    heat_cop.setDefaultValue(3.74)
    heat_cop.setDescription("Set the heat pump's heating coil rated COP to this value.")
    args << heat_cop

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    if !runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    # get COP argument as double
    heat_cop = runner.getDoubleArgumentValue('heat_cop', user_arguments)

    # check the COP input for reasonableness
    if heat_cop <= 0
      runner.registerError('Please enter a positive value for Rated COP.')
      return false
    end
    if heat_cop > 10
      runner.registerWarning("The requested Rated COP of #{heat_cop} seems unusually high")
    end

    # set heating coil rated COP for all heat pumps
    model.getObjectsByType('OS:Coil:Heating:WaterToAirHeatPump:EquationFit'.to_IddObjectType).each do |heatingobj|
      heatingobj = heatingobj.to_CoilHeatingWaterToAirHeatPumpEquationFit.get
      heatingobj.setRatedHeatingCoefficientofPerformance(heat_cop)
    end

    return true
  end
end

# register the measure to be used by the application
SetHeatPumpHeatingCoilRatedCop.new.registerWithApplication