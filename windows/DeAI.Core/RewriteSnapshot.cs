using System;

namespace DeAI;

public sealed record RewriteSnapshot(Preferences Preferences, PersonalEntry[] Lexicon, Skill Skill)
{
    public void Validate(Preferences preferences, PersonalEntry[] lexicon, Skill skill)
    {
        if (Preferences != preferences || !ReferenceEquals(Lexicon, lexicon) || Skill != skill)
            throw new InvalidOperationException("设置、词库或 Skill 已变化，请重新打开改写面板。");
    }
}
