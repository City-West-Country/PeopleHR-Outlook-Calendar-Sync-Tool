# Shared constants for the PeopleHR -> Outlook sync.

# Fixed GUID namespace for our custom single-value extended properties. Changing this
# would orphan every previously-synced event, so treat it as permanent.
$script:PeopleHrPropertyGuid = 'f1d2c3b4-a5e6-4789-9abc-0123456789ab'

# Property used to store the canonical PeopleHR UID directly on the Graph event so we can
# filter/identify managed events reliably (rather than parsing the body).
$script:PeopleHrUidPropertyId = "String {$($script:PeopleHrPropertyGuid)} Name PeopleHrUid"

# Property used to store a content hash so we can detect when an event needs updating.
$script:PeopleHrHashPropertyId = "String {$($script:PeopleHrPropertyGuid)} Name PeopleHrHash"

# Outlook category applied to every managed event. Acts as a second safety net: the tool
# only ever updates/deletes events that carry this category AND our UID property.
$script:PeopleHrCategory = 'PeopleHR Sync'

# Marker still written into the event body for human visibility / backwards compatibility.
$script:PeopleHrUidBodyPrefix = 'PeopleHR-UID:'
