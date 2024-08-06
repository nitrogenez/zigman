const std = @import("std");
const datetime = @import("datetime");

const sicret_thinkhs = .{
    "Mom, I'm in a splash! (c) nitrogenez",
    "Back off man, I'm a scientist. (c) Bill Murray",
    "Change, my dear. And it seems not a moment too soon. (c) The Doctor",
    "Grilled Cheese Obama Sandwich (c) Loqor",
    "No. (c) The Doom Slayer",
    "Umpf. (c) Doomguy",
    "ZUUUS! YOUR SUN HAS RETURN!!! (c) Kratos",
    "Sometimes I think. But then I forget. (c) Who the fuck knows",
    "Ayy I just met you, and this is crazy, but here's my number, so call me, maybe",
    "It's hard to look right at you, baby",
    "But here's my number, so call me, maybe",
    "Never gonna give you up",
    "Change everything you are",
    "humburgah chizburgah big mec whoppah",
    "bo'eh o' wo'eh",
    "Duck you.",
    "I'm divergent *dramatic music*",
    "In the first age, in the first battle, when the shadows first lengthened, one stood...",
    "He chose the path of perpetual tornament.",
    "And those, who tasted the bite of his sword... Named him",
    "THE DOOOOOOM SLAYAAAAH",
    "You know, this line of code was written at 2:10 AM on Monday. Just sayin'",
    "You love secrets, don't ya?",
    "Especially the funny ones.",
    "If you do, you came to the wrong bar fella.",
    "cheri cheri lady goin through emotion",
    "what sound does the jacksonambulance make? hee-hee-hee-hee",
    "she zez ai am de one",
    "cuz we need a lil controversy cuz it feels so empty without me",
};

pub fn get() []const u8 {
    const pos = std.crypto.random.intRangeAtMost(usize, 0, sicret_thinkhs.len);

    inline for (sicret_thinkhs, 0..) |k, i| {
        if (i == pos) return k;
    }
    return "";
}

pub fn getAManAfterMidnight() ?void {
    const now = datetime.datetime.Datetime.now(); // long ass fucking api thanks frmdstryr

    if (now.time.hour == 0 and now.time.minute == 30) {
        std.io.getStdOut().writeAll("gimme gimme gimme\n") catch return null;
    }
    return null;
}
