package openlife.data.transition;

import openlife.settings.ServerSettings;
import openlife.server.Server;
import openlife.data.object.ObjectData;
import haxe.io.Path;
import sys.io.File;
import openlife.engine.Engine;
@:expose
class TransitionImporter
{
    public var transitions:Array<TransitionData> = [];
    public var categories:Array<Category> = [];
    private var categoriesById:Map<Int, Category> = [];

    // transitions without any last use transitions
    private var transitionsByActorIdTargetId:Map<Int, Map<Int, TransitionData>>;
    // transitions where both actor and target is last use
    private var lastUseBothTransitionsByActorIdTargetId:Map<Int, Map<Int, TransitionData>>;
    // transitions where only actor is last use
    private var lastUseActorTransitionsByActorIdTargetId:Map<Int, Map<Int, TransitionData>>;
    // transitions where only target is last use
    private var lastUseTargetTransitionsByActorIdTargetId:Map<Int, Map<Int, TransitionData>>;

    // maxUseTransitions
    private var maxUseTransitionsByActorIdTargetId:Map<Int, Map<Int, TransitionData>>;



    public function new()
    {

    }

    public function importCategories()
    {
        categories = [];
        categoriesById = [];

        for (name in sys.FileSystem.readDirectory(Engine.dir + "categories"))
        {
            var category = new Category(File.getContent(Engine.dir + 'categories/$name'));
            
            categories.push(category);
            categoriesById[category.parentID] = category;

        }
    }

    public function importTransitions()
    {        
        if(categories.length == 0) importCategories();

        transitions = [];
        transitionsByActorIdTargetId = [];
        lastUseBothTransitionsByActorIdTargetId = [];
        lastUseActorTransitionsByActorIdTargetId = [];
        lastUseTargetTransitionsByActorIdTargetId = [];

        maxUseTransitionsByActorIdTargetId = [];

        for (name in sys.FileSystem.readDirectory(Engine.dir + "transitions"))
        {
            
            var transition = TransitionData.createNewFromFile(Path.withoutExtension(name),File.getContent(Engine.dir + 'transitions/$name'));
            
            addTransition(transition);

            createAndaddCategoryTransitions(transition); 

        }

        trace('Transitions loaded: ${transitions.length}');
    }

    private function getTransitionMap(lastUseActor:Bool, lastUseTarget:Bool, maxUseTarget:Bool=false):Map<Int, Map<Int, TransitionData>>
    {
        if(maxUseTarget) return maxUseTransitionsByActorIdTargetId;

        if(lastUseActor && lastUseTarget)
        {
            return lastUseBothTransitionsByActorIdTargetId;
        }
        else if(lastUseActor && lastUseTarget == false)
        {
            return lastUseActorTransitionsByActorIdTargetId;
        }
        else if(lastUseActor == false && lastUseTarget)
        {
            return lastUseTargetTransitionsByActorIdTargetId;
        } 
        else
        {
            return transitionsByActorIdTargetId;
        }
    }

    private function getTransitionMapByTargetId(id:Int, lastUseActor:Bool, lastUseTarget:Bool, maxUseTarget:Bool=false):Map<Int, TransitionData>
    {
        var transitionMap = getTransitionMap(lastUseActor, lastUseTarget, maxUseTarget);

        var transitionsByTargetId = transitionMap[id];

        if(transitionsByTargetId == null){
            transitionsByTargetId = [];
            transitionMap[id] = transitionsByTargetId;
        }

        return transitionsByTargetId;
    }

    public function getTransition(actorId:Int, targetId:Int, lastUseActor:Bool = false, lastUseTarget:Bool = false, maxUseTarget:Bool=false):TransitionData{
        
        var transitionMap = getTransitionMap(lastUseActor, lastUseTarget, maxUseTarget);

        var transitionsByTargetId = transitionMap[actorId];

        if(transitionsByTargetId == null) return null;

        return transitionsByTargetId[targetId];
    }

    public function addTransition(transition:TransitionData,  lastUseActor:Bool = false, lastUseTarget:Bool = false){
        
        if(lastUseActor == false && lastUseTarget == false){
            // if transition is a reverse transition, it can be done also on lastUse Items so add Transaction for that
            if(transition.lastUseActor == false && transition.reverseUseActor && transition.lastUseTarget == false && transition.reverseUseTarget) addTransition(transition, true, true);
            else if(transition.lastUseActor == false && transition.reverseUseActor) addTransition(transition, true, transition.lastUseTarget);
            else if(transition.lastUseTarget == false && transition.reverseUseTarget) addTransition(transition, transition.lastUseActor, true);
        }
        else{
            transition = transition.clone();
            if(lastUseActor) transition.lastUseActor = true;
            if(lastUseTarget) transition.lastUseTarget = true;
        }
       
        var transitionsByTargetId = getTransitionMapByTargetId(transition.actorID, transition.lastUseActor, transition.lastUseTarget);
        var trans = transitionsByTargetId[transition.targetID];
        
        if(trans == null)
        {
            this.transitions.push(transition);
            transitionsByTargetId[transition.targetID] = transition;

            transition.traceTransition("", ServerSettings.traceTransitionByTargetDescription);

            //if(transition.reverseUseTarget) traceTransition(transition, "", "");
            return;
        }

        // handle double transitions

        // add max use transitions that change target like in case of a well site with max stones or Canada Goose Pond with max
        // 33 + 1096 = 0 + 1096 targetRemains: true
        // 33 + 1096 = 0 + 3963 targetRemains: false
        if(trans.targetRemains && transition.targetRemains == false)
        {
            trans.traceTransition("1maxUseTransition targetRemains true: ", ServerSettings.traceTransitionByTargetDescription);
            transition.traceTransition("1maxUseTransition targetRemains: false: ", ServerSettings.traceTransitionByTargetDescription);

            var maxUseTransitionsByTargetId = getTransitionMapByTargetId(transition.actorID, false, false, true);
            maxUseTransitionsByTargetId[transition.targetID] = transition;

            this.transitions.push(transition);

            return;
        }

        if(trans.targetRemains == false && transition.targetRemains)
        {
            transition.traceTransition( "2maxUseTransition targetRemains: true", ServerSettings.traceTransitionByTargetDescription);
            trans.traceTransition("2maxUseTransition targetRemains: false:", ServerSettings.traceTransitionByTargetDescription);

            var maxUseTransitionsByTargetId = getTransitionMapByTargetId(transition.actorID, false, false, true);

            this.transitions.push(transition);
            transitionsByTargetId[transition.targetID] = transition;
            maxUseTransitionsByTargetId[trans.targetID] = trans;

            return;
        }

        // TODO there are a lot of double transactions, like Oil Movement, Horse Stuff, Fence / Wall Alignment, Rose Seed
        trans.traceTransition("WARNING DOUBLE 1!!", ServerSettings.traceTransitionByTargetDescription);
        transition.traceTransition("WARNING DOUBLE 2!!", ServerSettings.traceTransitionByTargetDescription);
    }

    // seems like obid can be at the same time a category and an object / Cabbage Seed + Bowl of Cabbage Seeds / 1206 + 1312
    // so better look also for @ in the description
    public function getCategory(id:Int) : Category
    {
        //var objectData = ObjectData.getObjectData(id);

        //if(objectData == null) return null;

        // TODO there was a reason for checking for @, but 1206 (Cabbage Seed) is an object and an category so wont work for this
        //if(objectData.description.indexOf("@") == -1) return null;

        return categoriesById[id];
    }

    public function createAndaddCategoryTransitions(transition:TransitionData){

        var actorCategory = getCategory(transition.actorID);
        var targetCategory = getCategory(transition.targetID);

        var bothActionAndTargetIsCategory = (actorCategory != null) && (targetCategory != null);

        if(bothActionAndTargetIsCategory)
        {
            // TODO many strange transitions to look at...
            //traceTransition(transition, 'bothActionAndTargetIsCategory: ');
            //return;
        }
             
        // add some pile target transitions
        // 1601 + 1600 = 0 + 1600
        // 1601 + 1601
        // 0 + 1600 = 1601 + 1601 (last)
        // 0 + 1600 = 1601 + 1600 
        var isPileTransition = targetCategory != null && (targetCategory.parentID == 1600 || targetCategory.parentID == 1601);
        isPileTransition = isPileTransition || (actorCategory != null && (actorCategory.parentID == 1600 || actorCategory.parentID == 1601));

        if(isPileTransition) 
        {
            //trace(transition);

            var pileCategory = getCategory(1600);
            var pileItemsCategory = getCategory(1601);

            for(i in 0...pileCategory.ids.length)
            {
                var newTransition = transition.clone();

                if(newTransition.actorID == 1601) newTransition.actorID = pileItemsCategory.ids[i];
                if(newTransition.targetID == 1600) newTransition.targetID = pileCategory.ids[i];
                else if(newTransition.targetID == 1601) newTransition.targetID = pileItemsCategory.ids[i];
                
                if(newTransition.newActorID == 1601) newTransition.newActorID = pileItemsCategory.ids[i];
                if(newTransition.newTargetID == 1600) newTransition.newTargetID = pileCategory.ids[i];
                else if(newTransition.newTargetID == 1601) newTransition.newTargetID = pileItemsCategory.ids[i];

                addTransition(newTransition);
            }
            
            return;
        }

        var category = actorCategory;

        if(category != null){
            for(id in category.ids){                 
                if(targetCategory == null){
                    var newTransition = transition.clone();
                    newTransition.actorID = id;
                    if(newTransition.newActorID == category.parentID) newTransition.newActorID = id;

                    addTransition(newTransition);
                } 
                // TODO both category may not be needed
                else{
                    for(targetId in targetCategory.ids){

                        var newTransition = transition.clone();
                        newTransition.actorID = id;
                        newTransition.targetID = targetId;

                        if(newTransition.newActorID == category.parentID) newTransition.newActorID = id;
                        if(newTransition.newTargetID == targetCategory.parentID) newTransition.newTargetID = targetId;

                        addTransition(newTransition);
                        //traceTransition(newTransition, 'bothActionAndTargetIsCategory: ');

                    }
                }
            }
        }

        if(bothActionAndTargetIsCategory) return;

        // for transitions where actor is no category but target is a category
        category = targetCategory;

        if(category != null){
            for(id in category.ids){

                var newTransition = transition.clone();
                newTransition.targetID = id;
                if(newTransition.newTargetID == category.parentID) newTransition.newTargetID = id;

                addTransition(newTransition); 
            }
        }
    }
}