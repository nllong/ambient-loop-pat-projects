class AmbientLoopTemperatureSetpoint < OpenStudio::Ruleset::ModelUserScript
  def name
    return "Ambient Loop Temperature Setpoint"
  end

  def description
    return "Set the temperature of the ambient loop to a specific value."
  end

  def modeler_description
    return "There are naming restrictions in this measure. Plant loop must be named 'Ambient Loop'"
  end

  # define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # the name of the space to add to the model
    setpoint = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("setpoint_temperature", true)
    setpoint.setUnits("Degrees Celsius")
    setpoint.setDisplayName("Ambient Loop Temperature")
    setpoint.setDefaultValue(20)
    setpoint.setDescription("Temperature setpoint for the ambient loop")
    args << setpoint

    delta = OpenStudio::Ruleset::OSArgument.makeDoubleArgument("design_delta", true)
    delta.setUnits("Delta Temperature")
    delta.setDefaultValue(5.55) # 10 Deg F default delta
    delta.setDisplayName("Delta Design Loop Temperature")
    delta.setDescription("Delta design temperature for the ambient loop")
    args << delta

    return args
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    # use the built-in error checking
    return false unless runner.validateUserArguments(arguments(model), user_arguments)

    # assign the user inputs to variables
    setpoint = runner.getDoubleArgumentValue("setpoint_temperature", user_arguments)
    delta = runner.getDoubleArgumentValue("design_delta", user_arguments)

    # This measure only works with the predifined loop name of `Ambient Loop`
    plant_loop = model.getPlantLoopByName('Ambient Loop').get

    # try and set the temperature of the ambient loop - this includes setting the
    # plant loop min/max temperatures, the sizing plant objects, and the schedules
    loop_sizing = plant_loop.sizingPlant
    loop_sizing.setDesignLoopExitTemperature(setpoint)
    loop_sizing.setLoopDesignTemperatureDifference(delta)

    plant_loop.supplyOutletNode.setpointManagers.each {|sm| sm.remove}

    amb_loop_schedule = OpenStudio::Model::ScheduleRuleset.new(model)
    amb_loop_schedule.setName("Ambient Loop Temperature Ruleset")
    amb_loop_schedule.defaultDaySchedule.setName("Ambient Loop Temperature - Default")
    amb_loop_schedule.defaultDaySchedule.addValue(OpenStudio::Time.new(0, 24, 0, 0), setpoint)

    amb_stpt_manager = OpenStudio::Model::SetpointManagerScheduled.new(model, amb_loop_schedule)
    amb_stpt_manager.setName('Ambient Loop Setpoint Manager - Scheduled')
    amb_stpt_manager.setControlVariable("Temperature")
    amb_stpt_manager.addToNode(plant_loop.supplyOutletNode)

    # report final condition of model
    runner.registerFinalCondition("The final maximum loop temperature is: #{setpoint}")

    return true
  end
end

# register the measure to be used by the application
AmbientLoopTemperatureSetpoint.new.registerWithApplication
