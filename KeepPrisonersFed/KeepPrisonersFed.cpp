#include <kenshi/Character.h>
#include <kenshi/MedicalSystem.h>
#include <kenshi/Faction.h>
#include <kenshi/Building/Building.h>
#include <kenshi/Enums.h>
#include <kenshi/util/hand.h>
#include <core/Functions.h>
#include <Debug.h>

static const float TARGET_HUNGER = 100.0f;

static bool isPlayerCagedForeigner(Character* character)
{
	if (character == NULL)
		return false;

	if (character->inSomething != IN_PRISON)
		return false;

	if (!character->hasFaction())
		return false;

	Faction* characterFaction = character->_NV_getFaction();
	if (characterFaction == NULL || characterFaction->isThePlayer())
		return false;

	Building* cage = character->inWhat.getBuilding();
	if (cage == NULL)
		return false;

	if (cage->_NV_getSpecialFunction() != BF_CAGE)
		return false;

	Faction* cageFaction = cage->_NV_getFaction();
	return cageFaction != NULL && cageFaction->isThePlayer();
}

void (*MedicalSystem__periodicUpdate_orig)(MedicalSystem* thisptr);
void MedicalSystem__periodicUpdate_hook(MedicalSystem* thisptr)
{
	MedicalSystem__periodicUpdate_orig(thisptr);

	if (isPlayerCagedForeigner(thisptr->me))
		thisptr->hunger = TARGET_HUNGER;
}

__declspec(dllexport) void startPlugin()
{
	if (KenshiLib::SUCCESS != KenshiLib::AddHook(KenshiLib::GetRealAddress(&MedicalSystem::_NV_periodicUpdate), &MedicalSystem__periodicUpdate_hook, &MedicalSystem__periodicUpdate_orig))
		ErrorLog("Keep Prisoners Fed: could not install hook!");
}
