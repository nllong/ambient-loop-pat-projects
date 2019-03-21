# start the measure
class RemoveAllDoors < OpenStudio::Measure::ModelMeasure
  # human readable name
  def name
    # Measure name should be the title case of the class name.
    return 'Remove All Doors'
  end

  # human readable description
  def description
    return 'Removes all doors from building envelope.'
  end

  # human readable description of modeling approach
  def modeler_description
    return 'Removes all doors from building envelope.'
  end

  # define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)

    ndoors =0

    model.getObjectsByType('OS:SubSurface'.to_IddObjectType).each do |subsurface|
      subsurface = subsurface.to_SubSurface.get
      if subsurface.subSurfaceType == 'Door'
        ndoors = ndoors + 1
        subsurface.remove
      end
    end

    # report final condition of model
    runner.registerFinalCondition("A total of #{ndoors} were removed from the building envelope.")

    return true
  end
end

# register the measure to be used by the application
RemoveAllDoors.new.registerWithApplication
