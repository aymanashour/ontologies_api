class MappingsController < ApplicationController

  # Get mappings for a class
  get '/ontologies/:ontology/classes/:cls/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    ontology = LinkedData::Models::Ontology.find(acronym).first

    cls_id = @params[:cls]
    cls = LinkedData::Models::Class.find(RDF::URI.new(cls_id)).in(submission).first
    reply 404, "Class with id `#{class_id}` not found in ontology `#{acronym}`" if cls.nil?


    mappings = LinkedData::Models::Mapping.where(terms: [ontology: ontology, term: cls.id ])
                                 .include(terms: [ :term, ontology: [ :acronym ] ])
                                 .include(process: [:name, :owner ])
                                 .all

    reply mappings
  end

  # Get mappings for an ontology
  get '/ontologies/:ontology/mappings' do
    ontology = ontology_from_acronym(@params[:ontology])
    page, size = page_params
    mappings = LinkedData::Models::Mapping.where(terms: [ontology: ontology ])
                                 .include(terms: [ :term, ontology: [ :acronym ] ])
                                 .include(process: [:name, :owner ])
                                 .page(page,size)
                                 .all
    reply mappings
  end

  namespace "/mappings" do
    # Display all mappings
    get do
      #calls to retrieve all mappings should not be allowed
      #users can do this by traversing all ontologies
      error(405,"To traverse all mappings one should traverse all mappings by ontology. See")
    end

    # Display a single mapping
    get '/:mapping' do
      mapping_id = RDF::URI.new(params[:mapping])
      mapping = LinkedData::Models::Mapping.find(mapping_id)
                  .include(terms: [:ontology, :term ])
                  .include(process: LinkedData::Models::MappingProcess.attributes)
                  .first
      if mapping
        reply(200,mapping)
      else
        error(404, "Mapping with id `#{mapping_id.to_s}` not found")
      end
    end

    # Create a new mapping
    post do
      error(400, "Input does not contain terms") if !params[:terms]
      error(400, "Input does not contain at least 2 terms") if params[:terms].length < 2
      error(400, "Input does not contain mapping relation") if !params[:relation]
      error(400, "Input does not contain user creator ID") if !params[:creator]
      ontologies = {}
      params[:terms].each do |term|
        if !term[:term] || !term[:ontology]
          error(400,"Every term must have at least one term ID and a ontology ID or acronym")
        end
        if !term[:term].is_a?(Array)
          error(400,"Term IDs must be contain in Arrays")
        end
        o = term[:ontology]
        o =  o.start_with?("http://") ? o : ontology_uri_from_acronym(o)
        o = LinkedData::Models::Ontology.find(RDF::URI.new(o))
                                        .include(submissions: [:submissionId, :submissionStatus]).first
        error(400, "Ontology with ID `#{term[:ontology]}` not found") if o.nil?
        term[:term].each do |id|
          error(400, "Term ID #{id} is not valid, it must be an HTTP URI") if !id.start_with?("http://")
          submission = o.latest_submission
          error(400, "Ontology with id #{term[:ontology]} does not have parsed valid submission") if !submission
          c = LinkedData::Models::Class.find(RDF::URI.new(id)).in(o.latest_submission)
          error(400, "Class ID `#{id}` not found in `#{submission.id.to_s}`") if c.nil?
        end
      end
      user_id = params[:creator].start_with?("http://") ? params[:creator].split("/")[-1] : params[:creator]
      user_creator = LinkedData::Models::User.find(user_id).include(:username).first
      error(400, "User with id `#{params[:creator]}` not found") if user_creator.nil?
      process = LinkedData::Models::MappingProcess.new(:creator => user_creator, :name => "REST Mapping")
      process.relation = RDF::URI.new(params[:relation])
      process.date = DateTime.now
      process_fields = [:source,:source_name, :comment]
      process_fields.each do |att|
        process.send("#{att}=",params[att]) if params[att]
      end
      process.save
      term_mappings = []
      params[:terms].each do |term|
        ont_acronym = term[:ontology].start_with?("http://") ? term[:ontology].split("/")[-1] : term[:ontology]
        term_mappings << LinkedData::Mappings.create_term_mapping(term[:term].map {|x| RDF::URI.new(x) },ont_acronym)
      end
      mapping_id = LinkedData::Mappings.create_mapping(term_mappings)
      LinkedData::Mappings.connect_mapping_process(mapping_id, process)
      mapping = LinkedData::Models::Mapping.find(mapping_id)
                  .include(terms: [:ontology, :term ])
                  .include(process: LinkedData::Models::MappingProcess.attributes)
                  .first
      reply(201,mapping)
    end

    # Update via delete/create for an existing submission of an mapping
    put '/:mapping' do
      reply(405, "post is not supported for mappings")
    end

    # Update an existing submission of an mapping
    patch '/:mapping' do
      #reply not supported
      reply(405, "patch is not supported for mappings")
    end

    # Delete a mapping
    delete '/:mapping' do
    end
  end

  namespace "/mappings/statistics" do
    # List recent mappings
    get '/recent' do
    end

    get '/ontologies/' do
      counts = {}
      onts = LinkedData::Models::Ontology.where.include(:acronym).all
      onts.each do |o|
        counts[o.acronym] = LinkedData::Models::Mapping.where(terms: [ontology: o])
                               .count
      end
      reply counts
    end

    # Statistics for an ontology
    get '/ontologies/:ontology' do
      ontology = ontology_from_acronym(@params[:ontology])
      counts = {}
      other = LinkedData::Models::Ontology
                                 .where(term_mappings: [ mappings: [  terms: [ ontology: ontology ]]])
                                 .include(:acronym)
                                 .all
      other.each do |o|
        next if o.acronym == ontology.acronym
        counts[o.acronym] = LinkedData::Models::Mapping.where(terms: [ontology: o])
                               .and(terms: [ontology: ontology])
                               .count
      end
      reply counts
    end

    # Classes with lots of mappings
    get '/ontologies/:ontology/popular_classes' do
    end

    # Users with lots of mappings
    get '/ontologies/:ontology/users' do
    end
  end

end
