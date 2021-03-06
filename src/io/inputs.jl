""
function prepare_network_case(network_file::String; events::Vector{<:Dict{String,Any}}=Vector{Dict{String,Any}}([]))::Tuple{Dict{String,Any},Dict{String,Any}}
    data_dss = PMD.parse_dss(network_file)

    # TODO: explicitly support DELTA connected generators in LPUBFDiag
    for type in ["pvsystem", "generator"]
        if haskey(data_dss, type)
            for (_,obj) in data_dss[type]
                obj["conn"] = PMD.WYE
            end
        end
    end

    data_eng = PMD.parse_opendss(data_dss; import_all=true)

    # Allow all loads to be sheddable
    for (_,load) in data_eng["load"]
        load["dispatchable"] = PMD.YES
    end

    data_eng["voltage_source"]["source"]["pg_lb"] = zeros(length(data_eng["voltage_source"]["source"]["connections"]))
    data_eng["time_elapsed"] = 1.0  # 24 hours by default, 1 hr steps

    PMD.apply_voltage_bounds!(data_eng)

    # PMD.make_lossless!(data_eng)

    mn_data_eng = PMD._build_eng_multinetwork(data_eng)

    apply_events!(mn_data_eng, events)

    return data_eng, mn_data_eng
end


""
function parse_events(events_file::String)::Vector{Dict{String,Any}}
    open(events_file, "r") do f
        JSON.parse(f)
    end
end


""
function parse_inverters(inverter_file::String)::Dict{String,Any}
    PowerModelsStability.parse_json(inverter_file)
end


""
function parse_protection_tables(protection_file::String)::Dict{NamedTuple,Dict{String,Any}}
    _tables = Dict()

    XLSX.openxlsx(protection_file, mode="r") do xf
        for sheet_name in XLSX.sheetnames(xf)
            _tables[sheet_name] = DataFrames.DataFrame(XLSX.gettable(xf[sheet_name])...)
        end
    end

    _configs = haskey(_tables, "Configuration") ? _tables["Configuration"] : _tables["ConfigTable"]
    _switches = [n for n in names(_configs) if !startswith(n, "Config")]
    _namedtuple_names = Tuple(Symbol(replace(sw, "'" => "")) for sw in _switches)

    configurations = Dict{String,NamedTuple}()
    for (i, row) in enumerate(eachrow(_configs))
        configurations["S$i"] = NamedTuple{_namedtuple_names}(Tuple(lowercase(string(PMD.SwitchState(row[sw]))) for sw in _switches))
        configurations["Sg$i"] = NamedTuple{_namedtuple_names}(Tuple(lowercase(string(PMD.SwitchState(row[sw]))) for sw in _switches))
        # TODO how to deal with Sg configs?
    end

    protection_data = Dict{NamedTuple,Dict{String,Any}}()
    for (name, table) in _tables
        if name != "Configuration" && name != "ConfigTable"
            protection_data[configurations[name]] = Dict{String,Any}(col => table[!, col] for col in names(table))
        end
    end

    return protection_data
end


""
function parse_faults(faults_file::String)::Dict{String,Any}
    JSON.parsefile(faults_file)
end
