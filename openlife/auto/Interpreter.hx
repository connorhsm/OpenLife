package openlife.auto;

import openlife.data.object.ObjectData;
import haxe.ds.Vector;

class Interpreter
{
    var list:Vector<Int>;
    public function new(list:Vector<Int>)
    {
        this.list = list;
    }
    public function stringNumber(string:String):Int
    {
        return switch (string)
        {
            case "one": 1;
            case "two": 2;
            case "three": 3;
            case "four": 4;
            case "five": 5;
            case "six": 6;
            case "seven": 7;
            case "eight": 8;
            case "nine": 9;
            case "ten": 10;
            case "eleven": 11;
            case "twevle": 12;
            case "thirteen": 13;
            case "fourteen": 14;
            case "fiveteen": 15;
            case "cart": 4;
            case "basket": 3;
            default: 1;
        }
    }
    public function stringObject(string:String):Int
    {
        for (id in list)
        {
            var desc = new ObjectData(id,true).description.toUpperCase();
            if (desc.indexOf(string) != -1) return id;
        }
        return 0;
    }
}