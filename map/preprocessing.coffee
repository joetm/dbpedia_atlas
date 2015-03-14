_preprocess = (data, untyped_data, stats_data) ->
    map.leaf_regions = topojson.feature(data, data.objects.leaf_regions).features
    geometries = data.objects.leaf_regions.geometries
    
    ### parse paths into arrays, and extract the class of each leaf region ###
    map.leaf_regions.forEach (f) ->
        f.properties.path = JSON.parse(f.properties.path)
        f.properties.class = f.properties.path[f.properties.path.length-1]
        
    ### presimplify the topologies (compute the effective area (z) of each point) ###
    topojson.presimplify(data)
    topojson.presimplify(untyped_data)
    
    ### store all leaf_regions into the ontology tree, and store each node within the feature's properties ###
    map.leaf_regions.forEach (f) ->
        n = ontology.get_node_from_class(f.properties.class)
        n.leaf_region = f
        f.properties.node = n
        
    ### compute merged regions from leaf regions ###
    _merge = (n, depth) ->
        n.merged_region = topojson.merge(data, geometries.filter (g) -> g.properties.path.length > depth and g.properties.path[depth] is n.name)
        
        if n.children?
            n.children.forEach (c) -> _merge(c, depth+1)
        
    _merge(ontology.tree, 0)
    
    ### compute all region centroids ###
    ontology.nodes.forEach (n) ->
        [n.x, n.y] = path_generator.centroid n.merged_region
        
    ### compute all region areas ###
    ontology.nodes.forEach (n) ->
        n.area = path_generator.area n.merged_region
        
    ### create a stats index ###
    _stats = {}
    stats_data.forEach (s) -> _stats[s.class] = s
    
    ### add stats to each leaf region ###
    map.leaf_regions.forEach (f) ->
        f.properties.node.stats = _stats[f.properties.node.name]
        
        console.error "Class not found in statistics data: #{f.properties.node.name}" if not f.properties.node.stats?
        
    ### compute additional stats ###
    map.leaf_regions.forEach (f) ->
        f.properties.node.stats.triple_density = f.properties.node.stats.triple_count / f.properties.node.leaf_count
        f.properties.node.stats.obj_props_density = f.properties.node.stats.obj_props_count / f.properties.node.leaf_count
        f.properties.node.stats.data_props_density = f.properties.node.stats.data_props_count / f.properties.node.leaf_count
        
    ### define readable, plural, multiline labels for level one regions ###
    _readable_labels =
        'Place': ['Places']
        'Agent': ['Agents']
        'Event': ['Events']
        'Species': ['Species']
        'Work': ['Works']
        'SportsSeason': ['Sports', 'Seasons']
        'UnitOfWork': ['Units of', 'Work']
        'TopicalConcept': ['Topical', 'Concepts']
        'Biomolecule': ['Biomolecules']
        'Activity': ['Activities']
        'Food': ['Food']
        'MeanOfTransportation': ['Means of', 'Transportation']
        'Device': ['Devices']
        'CelestialBody': ['Celestial', 'Bodies']
        'ChemicalSubstance': ['Chemical', 'Substances']
        'Medicine': ['Diseases'] # FIXME why are they called Medicine?
        'TimePeriod': ['Time', 'Periods']
        'Satellite': ['Satellites']
        'SportCompetitionResult': ['Sport', 'Competition', 'Results']
        'AnatomicalStructure': ['Anatomical', 'Structures']
        'GeneLocation': ['Gene', 'Locations']
        'CareerStation': ['Career', 'Stations']
        'PersonFunction': ['Person', 'Functions']
        'gml:_Feature': ['gml:feature']
        'Language': ['Languages']
        'Sales': ['Sales']
        'Drug': ['Drugs']
        'EthnicGroup': ['Ethnic', 'Groups']
        'Award': ['Awards']
        'Colour': ['Colours']
        'Holiday': ['Holidays']
        'Currency': ['Currencies']
        'SnookerWorldRanking': ['Snooker','World','Rankings']
        'Swarm': ['Swarms']
        'Competition': ['Competitions']
        'List': ['Lists']
        'Name': ['Names']
        
    ontology.levels[1].forEach (n) ->
        n.readable_label = _readable_labels[n.name]
        
_preprocess_selection = (selection) ->
    ### compute cartesian coordinates ###
    [selection.x, selection.y] = _ij_to_xy(selection.i, selection.j)
    
    ### compute selection parent, if any ###
    if selection.path.length > 0
        selection.parent = ontology.get_node_from_class(selection.path[selection.path.length-1])
    else
        selection.parent = null
        
    ### extract relational links ###
    ### FIXME links to self are currently ignored ###
    selection.relations = []
    
    ### outgoing links ###
    selection.object_properties.outgoing.forEach (t) ->
        if 'i' of t and 'j' of t
            [ox, oy] = _ij_to_xy(t.i.value, t.j.value)
            path = ontology.get_path(t.c)
            
            selection.relations.push {
                source: selection,
                predicate: t.p.value,
                target: {
                    uri: t.o.value,
                    i: t.i.value,
                    j: t.j.value,
                    x: ox,
                    y: oy,
                    parent: if path.length > 0 then ontology.get_node_from_class(path[path.length-1]) else null
                }
            }
        else
            console.error('Link to out-of-map entity: ' + t.o.value)
        
    ### incoming links ###
    selection.object_properties.incoming.forEach (t) ->
        if 'i' of t and 'j' of t
            [sx, sy] = _ij_to_xy(t.i.value, t.j.value)
            path = ontology.get_path(t.c)
            
            selection.relations.push {
                source: {
                    uri: t.s.value,
                    i: t.i.value,
                    j: t.j.value,
                    x: sx,
                    y: sy,
                    parent: if path.length > 0 then ontology.get_node_from_class(path[path.length-1]) else null
                },
                predicate: t.p.value,
                target: selection
            }
        else
            console.error('Link from out-of-map entity: ' + t.s.value)
            
    ### pointers relative to current selection ###
    selection.relations.forEach (r) ->
        if r.source is selection
            r.start = r.source
            r.end = r.target
        else
            r.start = r.target
            r.end = r.source
            