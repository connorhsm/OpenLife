package states.game;

import data.MapData;
import data.MapData.MapInstance;
import data.PlayerData.PlayerInstance;
import data.PlayerData.PlayerMove;
import data.GameData;
import client.MessageTag;
import haxe.io.Bytes;

class Game extends states.State
{
    var dialog:Dialog;
    var ground:Ground;
    var objects:Objects;
    var player:Player;
    var playerInstance:PlayerInstance;
    var mapInstance:MapInstance;
    var index:Int = 0;
    public var data:GameData;
    var compress:Bool = false;
    public function new()
    {
        super();
        data = new GameData();
        ground = new Ground(this);
        objects = new Objects(this);
        dialog = new Dialog(this);
        addChild(ground);
        addChild(objects);
        addChild(dialog);
        //connect
        //login
        Main.client.login.email = "test@test.co.uk";
        Main.client.login.key = "WC2TM-KZ2FP-LW5A5-LKGLP";
        Main.client.login.accept = function()
        {
            trace("accept");
            //set message reader function to game
            Main.client.message = message;
            Main.client.login = null;
        }
        Main.client.login.reject = function()
        {
            trace("reject");
            Main.client.login = null;
        }
        //set message reader function to login
        Main.client.message = Main.client.login.message;
        //Main.client.connect("game.krypticmedia.co.uk",8007);
    }
    override function update()
    {
        super.update();
    }
    public function mapUpdate(x:Int,y:Int,sizeX:Int,sizeY:Int) 
    {
        var string:String = "";
        for(ys in y...y + sizeY)
        {
            for(xs in x...x + sizeX)
            {
                string = xs + "." + ys;
                data.map.floor.get(string);
                data.map.object.get(string);
                
            }
        }
    }
    public function message(input:String) 
    {
        switch(Main.client.tag)
        {
            case PLAYER_UPDATE:
            var array = input.split(" ");
            playerInstance = new PlayerInstance(input.split(" "));
            case PLAYER_MOVES_START:
            var playerMove = new PlayerMove(input.split(" "));
            if (data.playerMap.exists(playerMove.id))
            {
                
            }
            //p_id xs ys total_sec eta_sec trunc xdelt0 ydelt0
            //264 0 -1 0.503 0.503 0 1 1
            case MAP_CHUNK:
            if(compress)
            {
                Main.client.tag = null;
                data.map.setRect(mapInstance.x,mapInstance.y,mapInstance.sizeX,mapInstance.sizeY,input,mapUpdate);
                mapInstance = null;
                //toggle to go back to istance for next chunk
                compress = false;
            }else{
                var array = input.split(" ");
                //trace("map chunk array " + array);
                for(value in array)
                {
                    switch(index++)
                    {
                        case 0:
                        mapInstance = new MapInstance();
                        mapInstance.sizeX = Std.parseInt(value);
                        case 1:
                        mapInstance.sizeY = Std.parseInt(value);
                        case 2:
                        mapInstance.x = Std.parseInt(value);
                        case 3:
                        mapInstance.y = Std.parseInt(value);
                        case 4:
                        mapInstance.rawSize = Std.parseInt(value);
                        case 5:
                        mapInstance.compressedSize = Std.parseInt(value);
                        //set min
                        data.map.setX = mapInstance.x < data.map.setX ? mapInstance.x : data.map.setX;
                        data.map.setY = mapInstance.y < data.map.setY ? mapInstance.y : data.map.setY;
                        //set max
                        data.map.setWidth = mapInstance.sizeX + mapInstance.x > data.map.setWidth ? mapInstance.sizeX + mapInstance.x : data.map.setWidth;
                        data.map.setHeight = mapInstance.sizeY + mapInstance.y > data.map.setHeight ? mapInstance.sizeY + mapInstance.y : data.map.setHeight;
                        trace("map chunk " + mapInstance.toString());
                        index = 0;
                        //set compressed size wanted
                        Main.client.compress = mapInstance.compressedSize;
                        compress = true;
                    }
                }
            }
            case MAP_CHANGE:
            //x y new_floor_id new_id p_id optional oldX oldY speed
            var mapChange = new MapChange(input.split(" "));
            case HEAT_CHANGE:
            //trace("heat " + input);

            case FOOD_CHANGE:
            //trace("food change " + input);
            //also need to set new movement move_speed: is floating point speed in grid square widths per second.
            case FRAME:
            Main.client.tag = "";
            case PLAYER_SAYS:
            trace("player say " + input);
            dialog.say(input);
            case PLAYER_OUT_OF_RANGE:
            //player is out of range

            case LINEAGE:
            //p_id mother_id grandmother_id great_grandmother_id ... eve_id eve=eve_id

            case NAME:
            //p_id first_name last_name last_name may be ommitted.

            case DYING:
            //p_id isSick isSick is optional 1 flag to indicate that player is sick (client shouldn't show blood UI overlay for sick players)

            case HEALED:
            //p_id player healed no longer dying.

            case MONUMENT_CALL:
            //MN x y o_id monument call has happened at location x,y with the creation object id

            case GRAVE:
            //x y p_id

            case GRAVE_MOVE:
            //xs ys xd yd swap_dest optional swap_dest parameter is 1, it means that some other grave at  destination is in mid-air.  If 0, not

            case GRAVE_OLD:
            //x y p_id po_id death_age underscored_name mother_id grandmother_id great_grandmother_id ... eve_id eve=eve_id
            //Provides info about an old grave that wasn't created during your lifetime.
            //underscored_name is name with spaces replaced by _ If player has no name, this will be ~ character instead.

            case OWNER_LIST:
            //x y p_id p_id p_id ... p_id

            case VALLEY_SPACING:
            //y_spacing y_offset Offset is from client's birth position (0,0) of first valley.

            case FLIGHT_DEST:
            //p_id dest_x dest_y
            trace("FLIGHT FLIGHT FLIGHT " + input.split(" "));
            default:
        }
    }
}