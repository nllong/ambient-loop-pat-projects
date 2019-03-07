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

    cop = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("cop", true)
    cop.setDisplayName("Cooling Coil Rated COP")
    cop.setDefaultValue(3.74)
    cop.setDescription("Set the heat pump's heating coil rated COP to this value.")
    args << cop

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
    cop = runner.getDoubleArgumentValue('cop', user_arguments)

    # check the COP input for reasonableness
    if cop <= 0
      runner.registerError('Please enter a positive value for Rated COP.')
      return false
    end
    if cop > 10
      runner.registerWarning("The requested Rated COP of #{cop} seems unusually high")
    end

    # set heating coil rated COP for all heat pumps
    model.getObjectsByType('OS:Coil:Heating:WaterToAirHeatPump:EquationFit'.to_IddObjectType).each do |heatingobj|
      heatingobj = heatingobj.to_CoilHeatingWaterToAirHeatPumpEquationFit.get
      heatingobj.setRatedHeatingCoefficientofPerformance(cop)
    end

    return true
  end
end

# register the measure to be used by the application
SetHeatPumpHeatingCoilRatedCop.new.registerWithApplication