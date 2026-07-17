using System.Text.Json;
using System.Text.Json.Serialization;

namespace OpenSynapse.Agent;

internal static class AgentJson
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        Converters = { new JsonStringEnumConverter(allowIntegerValues: false) }
    };
}
