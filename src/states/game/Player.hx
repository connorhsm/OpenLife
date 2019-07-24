package states.game;
#if openfl
import motion.MotionPath;
import motion.Actuate;
import openfl.display.Tile;
#end
import data.PlayerData.PlayerType;
import data.PlayerData.PlayerInstance;
import haxe.Timer;
import data.SpriteData;
import data.ObjectData;
import data.AnimationData;
import data.Point;
class Player #if openfl extends Object #end
{
    public var lastMove:Int = 1;
    public var moveTimer:Timer;
    public static var main:Player;
    public var instance:PlayerInstance;
    public var ageRange:Array<{min:Float,max:Float}> = [];
    public var game:Game;
    public var object:Object;
    public var moves:Array<Point> = [];
    public var velocityX:Float = 0;
    public var velocityY:Float= 0;
    //how many frames till depletion
    public var delay:Int = 0;
    public var time:Int = 0;
    var timeInt:Int = 0;
    //pathing
    public var goal:Bool = false;
    public function new(game:Game)
    {
        this.game = game;
        #if openfl
        super();
        #end
        type = PLAYER;
    }
    public function update()
    {
        if (timeInt == 0)
        {
            if (goal) path();
            move();
        }
        if (timeInt > 0)
        {
            //add to pos
            x += velocityX;
            y += -velocityY;
            //remove time per frame
            timeInt--;
        }
        if (delay > 0) delay--;
    }
    public function move()
    {
        //grab another move
        if(moves.length > 0)
        {
            var point = moves.pop();
            pos();
            instance.x += Std.int(point.x);
            instance.y += Std.int(point.y);
            //flip (change direction)
            if (point.x != 0)
            {
                if (point.x > 0)
                {
                    scaleX = 1;
                }else{
                    scaleX = -1;
                }
            }
            velocityX = (point.x * Static.GRID) / time;
            velocityY = (-point.y * Static.GRID) / time;  
            timeInt = time;
        }
    }
    public function step(mx:Int,my:Int):Bool
    {
        //no other move is occuring, and player is not moving on blocked
        if (timeInt > 0 || game.data.blocking.get(Std.string(instance.x + mx) + "." + Std.string(instance.y + my))) return false;
        //send data
        lastMove++;
        Main.client.send("MOVE " + instance.x + " " + instance.y + " @" + lastMove + " " + mx + " " + my);
        timeSpeed();
        moves = [new Point(mx,my)];
        return true;
    }
    public function timeSpeed()
    {
        //get floor speed
        var time = Static.GRID/(Static.GRID * instance.move_speed);
        this.time = Std.int(time * 60);
        timeInt = 0;
    }
    public function pathMove()
    {
        
    }
    public function path()
    {
        trace("path");
        var px:Int = game.program.goal.x - instance.x;
        var py:Int = game.program.goal.y - instance.y;
        trace("dis x " + px + " " + py);
        if (px != 0) px = px > 0 ? 1 : -1;
        if (py != 0) py = py > 0 ? 1 : -1;
        trace("path " + px + " " + py);
        if (px == 0 && py == 0)
        {
            //complete 
            game.program.stop();
        }else{
            if (!step(px,py))
            {
                //x
                px *= -1;
                if (!step(px,py))
                {
                    //y
                    px *= -1;
                    py *= -1;
                    if (!step(px,py))
                    {
                        //x and y
                        px *= -1;
                        if (!step(px,py))
                        {
                            
                        }
                    }
                }
            }
        }
        timeInt = time;
    }
    public function set(data:PlayerInstance)
    {
        instance = data;
        //trace("force " + instance.forced);
        if (instance.forced == 1) 
        {
            trace("forced");
            Main.client.send("FORCE " + instance.x + " " + instance.y);
        }
        //remove moves
        timeInt = 0;
        moves = [];
        //pos and age
        pos();
        age();
        hold();
    }
    public function hold()
    {
        //object holding
        if (instance.o_id == 0)
        {
            if (object != null) removeTile(object);
        }else{
            if (object != null)
            {
                if (object.id == Std.int(instance.o_id)) return;
                removeTile(object);
            }
            if (instance.o_id > 0)
            {
                //object
                object = game.objects.add(instance.o_id,0,0);
            }else{
                //player
                object = game.objects.add(Std.int(instance.o_id),0,0,true);
            }
            //remove from main objects display
            game.objects.removeTile(object);
            //add into player
            addTile(object);

            object.x = instance.o_origin_x;
            object.y = instance.o_origin_y;
        }
    }
    public function pos()
    {
        x = (instance.x - game.data.map.x - game.cameraX) * Static.GRID;
        y = (instance.y - game.data.map.y - game.cameraY) * Static.GRID;
    }
    public function age()
    {
        #if openfl
        var tile:Tile;
        for(i in 0...numSprites)
        {
            tile = get(i);
            tile.visible = true;
            if((ageRange[i].min > instance.age || ageRange[i].max < instance.age) && ageRange[i].min > 0)
            {
                tile.visible = false;
            }
        }
        #end
    }
}