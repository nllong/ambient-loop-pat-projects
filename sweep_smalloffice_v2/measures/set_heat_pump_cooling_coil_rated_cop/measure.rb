class SetHeatPumpCoolingCoilRatedCop < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    return "Set Heat Pump Cooling Coil Rated COP"
  end
  # human readable description
  def description
    return "Set heat pump cooling coil gross rated COP."
  end
  # human readable description of modeling approach
  def modeler_description
    return "Set heat pump cooling coil gross rated COP."
  end
  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    cool_cop = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("cool_cop", true)
    cool_cop.setDisplayName("Cooling Coil Rated COP")
    cool_cop.setDefaultValue(3.65)
    cool_cop.setDescription("Set the heat pump's cooling coil rated COP to this value.")
    args << cool_cop

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
    cool_cop = runner.getDoubleArgumentValue('cool_cop', user_arguments)

    # check the COP input for reasonableness
    if cool_cop <= 0
      runner.registerError('Please enter a positive value for Rated COP.')
      return false
    end
    if cool_cop > 10
      runner.registerWarning("The requested Rated COP of #{cool_cop} seems unusually high")
    end

    # set cooling coil rated COP for all heat pumps
    model.getObjectsByType('OS:Coil:Cooling:WaterToAirHeatPump:EquationFit'.to_IddObjectType).each do |coolingobj|
      coolingobj = coolingobj.to_CoilCoolingWaterToAirHeatPumpEquationFit.get
      coolingobj.setRatedCoolingCoefficientofPerformance(cool_cop)
    end

    return true
  end
end

# register the measure to be used by the application
SetHeatPumpCoolingCoilRatedCop.new.registerWithApplication