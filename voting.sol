// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17; 

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {

    /* ----- VARIABLES ----- */

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
        // Pour éviter le spam de propositions, le nombre de propositions envoyées par le voter est comptabilisé
        uint sentProposal; 
    }

    struct Proposal {
        string description;
        uint voteCount;
    }   

    // Tableau de variables à structure Proposal, qui permet de stocker les propositions
    Proposal[] proposals; 
    
    // Mapping whitelist, qui donne à chaque adresse rentrée une variable de structure Voter. 
    mapping (address => Voter) whitelist; 

    // Enumération des différents états possibles du Workflow
    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // Variable d'état qui contient les différents states possibles 
    WorkflowStatus private state; 
    // Variable d'état qui permet d'enregistrer la valeur de l'état actif
    uint8 statusValue; 

    /* ----- EVENTS ----- */ 

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);


    /* ----- CONSTRUCTOR -----*/

    // Constructor qui permet de whitelister automatiquement l'éxecuteur du contrat 
    constructor() {
        whitelist[msg.sender].isRegistered = true; 
    }

    /* ----- MODIFIER ----- */ 

    // Modifier permettant de contrôler si l'appel de la fonction est bien effectué par un électeur sur liste blanche
    modifier isWhiteListed() {
        require(whitelist[msg.sender].isRegistered, unicode"Vous n'êtes pas autorisé, cela nécessite d'être sur liste blanche");
        _; 
    }

    // Modifier permettant de contrôler qu'il y a bien des propositions enregistrées 
    modifier proposalsAreRegistered() {
        require(proposals.length >= 1, unicode"Il n'y a toujours pas de proposition enregistrée");
        _; 
    }

    // Modifier permettant de vérifier que l'id de proposition précisé correspond bien à un élément dans le tableau des propositions
    modifier isIndexExisting(uint _proposalId) {
        require (_proposalId < proposals.length, unicode"Le numéro précisé ne correspond à aucune proposition. Veuillez réitérer avec un numéro valide");
        _; 
    }

    // Modifier permet de vérifier que la session de vote est bien ouverte
    modifier isVotingStarted() {
        require(state == WorkflowStatus.VotingSessionStarted, "La session de vote n'est pas encore ouverte");
        _;
    }


    /* ----- FONCTIONS ----- */
    /*    Fonctions réservées à l'administateur    */ 

    // authorize permet à l'owner du contrat l'ajout d'électeurs sur la liste blanche, via leur adresse ethereum
    function authorize(address _address) external onlyOwner {
        // On vérifie que la session d'enregistrement des électeurs est bien ouverte
        require (state == WorkflowStatus.RegisteringVoters, unicode"Il n'est plus possible d'enregistrer d'électeurs sur liste blanche" ); 
        // On vérifie que l'adresse qu'on essaie de placer sur liste blanche n'est pas déjà listée
        require (!whitelist[_address].isRegistered, unicode"L'adresse est déjà sur liste blanche");

        // On enregistre le fait que cette adresse est sur liste blanche grâce à notre mapping
        whitelist[_address].isRegistered = true; 
        emit VoterRegistered(_address); 
    }

    // changeStatus permet de changer le statut en cours 
    function changeStatus() external onlyOwner {

        statusValue++; 

        // Si on souhaite clôturer la session d'enregistrement des propositions
        if (statusValue == 2 && proposals.length < 2 ) {
            revert("Il n'y a pas assez de propositions. Minimum requis : 2");
        }
        // Si on souhaite clôturer la session de vote 
        else if (statusValue == 4) {
            uint totalOfVotes; 
            // On utilise la fonction getTotalVotes qui comptabilise le nombre de votes reçus
            totalOfVotes = getTotalOfVotes(); 
            // On vérifie que il y'a au minimum 1 vote reçu pour pouvoir clôturer la session de vote 
            require(totalOfVotes > 0, unicode"Il n'est pas possible de clôturer la session de vote : aucun vote n'a été reçu");  
        }  else if (statusValue > 5) {
            revert (unicode"La session est déjà terminée");
        }

        state = WorkflowStatus(statusValue); 
        emit WorkflowStatusChange(WorkflowStatus(statusValue - 1), WorkflowStatus(statusValue)); 
    } 

    /*    Fonctions de proposition & de vote     */ 
  
    // sendProposals permet aux électeurs inscrits d'enregistrer leur propositions
    function sendProposals(string calldata _proposal) external isWhiteListed {

        // Variable permettant de définir le nombre maximum de propositions qu'un électeur peut soumettre
        uint8 maximumProposal = 3;

        // On vérifie que la session d'enregistrement des propositions est ouverte 
        require (state == WorkflowStatus.ProposalsRegistrationStarted, "La session d'enregistrement des propositions n'est pas ouverte" ); 
        // On vérifie que le soumetteur de proposition n'a pas dépassé le nombre maximum autorisé 
        require (whitelist[msg.sender].sentProposal < maximumProposal, unicode"Vous avez déjà soumis votre maximum de proposition autorisé");
        
        // On créée une variable proposal, ayant comme structure un schéma Proposal
        Proposal memory proposal; 
        // On définit comme description de la proposition le paramètre input de la fonction de type string
        proposal.description = _proposal; 
        // On ajoute dans notre tableau proposals l'instance de proposal créée auparavant 
        proposals.push(proposal); 

        // On incrémente le nombre de propositions enregistrées par l'électeur
        whitelist[msg.sender].sentProposal++;
        emit ProposalRegistered(proposals.length - 1);
    }


    // voteForProposal permet aux électeurs inscrits de voter pour la proposition que l'on souhaite 
    function voteForProposal(uint _proposalId) external isWhiteListed isIndexExisting(_proposalId) isVotingStarted {
        // On vérifie que la personne appelant la fonction n'a pas déjà voté 
        require(!(whitelist[msg.sender].hasVoted), unicode"Vous avez déjà voté pour votre proposition préférée !");

        // On comptabilise le vote en incrémentant la variable voteCount de la propositon indiquée en paramètre d'input de la fonction 
        proposals[_proposalId].voteCount++; 
        // On valide le fait que l'électeur a voté 
        whitelist[msg.sender].hasVoted = true; 
        // On vient associer à son adresse ethereum, l'ID de la proposition pour laquelle l'électeur a voté
        whitelist[msg.sender].votedProposalId = _proposalId; 
        emit Voted(msg.sender, _proposalId ); 
    }
 

    /*    Fonctions à but informatif   */ 

    // getAllProposals permet aux électeurs d'avoir accès aux propositions enregistrées  
    function getAllProposals() external view isWhiteListed proposalsAreRegistered returns(Proposal[] memory){
        return proposals; 
    }

    // getProposalByIndex permet aux électeurs de retrouver une proposition par son index 
    function getProposalByIndex(uint _proposalId) external view isWhiteListed proposalsAreRegistered isIndexExisting(_proposalId) returns(string memory) {
        return proposals[_proposalId].description;
    }

    // getVoteCountByProposal permet aux électeurs de savoir combien de votes a reçu une proposition
    function getVoteCountByProposal(uint _proposalId) external view isWhiteListed proposalsAreRegistered isIndexExisting(_proposalId) returns(uint) {
        return proposals[_proposalId].voteCount;
    }

    // getTotalOfVotes permet de connaître le total de votes enregistrés  
    function getTotalOfVotes() public view isWhiteListed isVotingStarted returns(uint) {
        uint totalOfVotes;  

        for(uint i = 0; i <= proposals.length - 1 ; i++) {
            // On ajoute à la variable la totalité votes comptabilisés 
            totalOfVotes += proposals[i].voteCount; 
        }   
        return totalOfVotes; 
    }

    // getWinner permet d'obtenir la proposition gagnante  
    function getWinner() public view returns(uint, string memory, uint) {  
        // On vérifie que la session de vote est fermée
        require(state >= WorkflowStatus.VotingSessionEnded, unicode"Il faut attendre que les votes soient comptabilisés.");

        // Variable qui correspond au plus gros nombre de vote comptabilisé
        uint biggestCount; 
        // Variable qui correspond à l'id de la proposition gagnante
        uint winningProposalId; 
        // Variable qui correspond au contenu de la proposition gagnante 
        string memory winningProposal; 

        // boucle for qui va venir parcourir l'ensemble des propositions 
        for(uint i = 0; i <= proposals.length - 1 ; i++) {
            // Si le plus gros compte est plus petit que le voteCount de la proposition survolée 
            // A la fin de la boucle, biggestCount sera égale au plus gros voteCount trouvé 
            if (biggestCount < proposals[i].voteCount) {
               // Alors le plus gros compte est égal au voteCount de la proposition survolée 
               biggestCount = proposals[i].voteCount;
               // On définit l'id gagnante via son index dans le tableau 
               winningProposalId = i;
               // On définit la proposition qui a reçu le plus de vote 
               winningProposal = proposals[i].description; 
           }
        }   
        // La fonction retourne la proposition gagnante, son index dans le tableau, et son nombre de voies reçues
        return (winningProposalId, winningProposal, biggestCount) ;
    }

    // hasVotedFor permet de voir pour quelle proposition, telle adresse a voté 
    function hasVotedFor(address _address) external view isWhiteListed returns(uint, string memory) {
        require(whitelist[_address].isRegistered, unicode"Cet électeur n'a pas pu enregistrer de vote");
        require(whitelist[_address].hasVoted, unicode"Cet électeur n'a pas enregistré de vote");
        return (whitelist[_address].votedProposalId, proposals[whitelist[_address].votedProposalId].description ); 
    }

    // getStatus permet de voir le state de la session active
    function getStatus() external view returns(string memory) {
        if (state == WorkflowStatus(0))  return ("RegisteringVoters, 0/5") ;
        if (state == WorkflowStatus(1))  return ("ProposalsRegistrationStarted, 1/5");
        if (state == WorkflowStatus(2))  return ("ProposalsRegistrationEnded, 2/5");
        if (state == WorkflowStatus(3))  return ("VotingSessionStarted, 3/5");
        if (state == WorkflowStatus(4))  return ("VotingSessionEnded, 4/5");
        if (state == WorkflowStatus(5))  return ("VotesTallied, 5/5");
        return ("");
    }
}