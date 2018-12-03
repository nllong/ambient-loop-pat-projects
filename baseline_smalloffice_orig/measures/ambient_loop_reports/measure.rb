# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'
require 'date'

#start the measure
class AmbientLoopReports < OpenStudio::Ruleset::ReportingUserScript

  # human readable name
  def name
    return "Ambient Loop Reports"
  end

  # human readable description
  def description
    return "Add report variables for post processing the ambient loop data."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Reporting Variables for Ambient Loop"
  end

  def log(str)
    puts "#{Time.now}: #{str}"
  end

  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # this measure does not require any user arguments, return an empty list
    return args
  end

  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

    result = OpenStudio::IdfObjectVector.new

    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return result
    end


    # Output:Variable,*,Facility Heating Setpoint Not Met Time,hourly; !- Zone Sum [hr]
    # Output:Variable,*,Facility Cooling Setpoint Not Met Time,hourly; !- Zone Sum [hr]
    # Output:Variable,*,Facility Heating Setpoint Not Met While Occupied Time,hourly; !- Zone Sum [hr]
    # Output:Variable,*,Facility Cooling Setpoint Not Met While Occupied Time,hourly; !- Zone Sum [hr]

    result << OpenStudio::IdfObject.load("Output:Variable,,District Cooling Inlet Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Cooling Outlet Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Cooling Mass Flow Rate,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Heating Inlet Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Heating Outlet Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Heating Mass Flow Rate,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Heating Hot Water Energy,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,District Cooling Chilled Water Energy,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,Site Mains Water Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,Site Outdoor Air Drybulb Temperature,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,,Site Outdoor Air Relative Humidity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Cooling:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Heating:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Variable,*,Zone Predicted Sensible Load to Setpoint Heat Transfer Rate,hourly,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Heating:Gas,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,InteriorLights:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Fans:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,InteriorEquipment:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,ExteriorLighting:Electricity,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Electricity:Facility,timestep;").get
    result << OpenStudio::IdfObject.load("Output:Meter,Gas:Facility,timestep;").get

    return result
  end

  def extract_timeseries_into_matrix(sqlfile, data, variable_name, key_value=nil)
    log "Executing query for #{variable_name}"
    if key_value
      ts = sqlfile.timeSeries('RUN PERIOD 1', 'Zone Timestep', variable_name, key_value)
    else
      ts = sqlfile.timeSeries('RUN PERIOD 1', 'Zone Timestep', variable_name)
    end
    log "Iterating over timeseries"
    column = [variable_name.gsub(":", "")] # Set the header of the data to the variable name, removing :
    unless ts.empty?
      ts = ts.get if ts.respond_to?(:get)
      ts = ts.first if ts.respond_to?(:first)

      start = Time.now
      # Iterating in OpenStudio can take up to 60 seconds with 10min data. The quick_proc takes 0.03 seconds.
      # for i in 0..ts.values.size - 1
      #   log "... at #{i}" if i % 10000 == 0
      #   column << ts.values[i]
      # end

      quick_proc = ts.values.to_s.split(',')

      # the first and last have some cleanup items because of the Vector method
      quick_proc[0] = quick_proc[0].gsub(/^.*\(/, '')
      quick_proc[-1] = quick_proc[-1].gsub(")", '')
      column += quick_proc

      log "Took #{Time.now - start} to iterate"
    end

    log "Appending column to data"

    # append the data to the end of the rows
    if column.size == data.size
      data.each_index do |index|
        data[index] << column[index]
      end
    end
    log "Finished extracting #{variable_name}"
  end

  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return false
    end

    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Cannot find last model.")
      return false
    end
    model = model.get

    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sqlFile = sqlFile.get
    model.setSqlFile(sqlFile)

    # create a new csv with the values and save to the reports direcoty.
    # assumptions:
    #   - all the variables exist
    #   - data are the same length

    # initialize the rows with the header
    puts "Starting to process Timeseries data"
    rows = [
        # Initial header row
        ['Date Time', 'Month', 'Day', 'Day of Week', 'Hour', 'Minute']
    ]

    # just grab one of the variables to get the date/time stamps
    ts = sqlFile.timeSeries('RUN PERIOD 1', 'Zone Timestep', 'Cooling:Electricity')
    if !ts.empty?
      ts = ts.first

      # Save off the date time values
      ts.dateTimes.each_with_index do |dt, index|
        rows << [DateTime.parse(dt.to_s).strftime("%m/%d/%Y %H:%M"), dt.date.monthOfYear.value, dt.date.dayOfMonth, dt.date.dayOfWeek.value, dt.time.hours, dt.time.minutes, ]
      end
    end

    # add in the other variables by columns -- should really pull this from the report variables defined above
    extract_timeseries_into_matrix(sqlFile, rows, 'Site Outdoor Air Drybulb Temperature', 'Environment')
    extract_timeseries_into_matrix(sqlFile, rows, 'Site Outdoor Air Relative Humidity', 'Environment')
    extract_timeseries_into_matrix(sqlFile, rows, 'Heating:Electricity')
    extract_timeseries_into_matrix(sqlFile, rows, 'Heating:Gas')
    extract_timeseries_into_matrix(sqlFile, rows, 'Cooling:Electricity')
    extract_timeseries_into_matrix(sqlFile, rows, 'Electricity:Facility')
    extract_timeseries_into_matrix(sqlFile, rows, 'Gas:Facility')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Heating Inlet Temperature', 'DISTRICT HEATING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Cooling Inlet Temperature', 'DISTRICT COOLING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Heating Outlet Temperature', 'DISTRICT HEATING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Cooling Outlet Temperature', 'DISTRICT COOLING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Heating Mass Flow Rate', 'DISTRICT HEATING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Cooling Mass Flow Rate', 'DISTRICT COOLING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Heating Hot Water Energy', 'DISTRICT HEATING 1')
    extract_timeseries_into_matrix(sqlFile, rows, 'District Cooling Chilled Water Energy', 'DISTRICT COOLING 1')

    # Figure out how to add this variable, probably by zone:
    # "Output:Variable,*,Zone Predicted Sensible Load to Setpoint Heat Transfer Rate,hourly,timestep;").get


    # sum up a couple of the columns and create a new column
    var_1 = nil
    var_2 = nil
    rows.each_with_index do |row, index|
      if index == 0
        runner.registerInfo(row.join(','))
        # Get the index of the columns to add
        var_1 = row.index('HeatingElectricity')
        var_2 = row.index('HeatingGas')

        if var_1 && var_2
          rows[index] << 'HeatingTotal'
          next
        else
          break
        end
      end

      runner.registerInfo("Index #{index}, Value 1 #{row[var_1]}, Value 2 #{row[var_2]}, Class #{row[var_1]}")
      runner.registerInfo("rows[index] class #{rows[index]}")
      rows[index] << row[var_1].to_f + row[var_2].to_f
    end

    # convert this to CSV object
    File.open('./report_timeseries.csv', 'w') do |f|
      rows.each do |row|
        f << row.join(',') << "\n"
      end
    end

    return true
  ensure
    sqlFile.close if sqlFile
  end
end

# register the measure to be used by the application
AmbientLoopReports.new.registerWithApplication
