// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./dependencies/ERC1155.sol";
import "./dependencies/Counters.sol";
import "./dependencies/EnumerableSet.sol";

contract TrongramHub is ERC1155 {
  using Counters for Counters.Counter;
  using EnumerableSet for EnumerableSet.UintSet;

  address public manager;

  uint256 public deployedAt;

  uint256 public constant BID_DURATION = 5 minutes; //30 minutes;
  uint256 public constant BID_STEP = 1000000;

  uint256 public constant STARS_ID = 0;

  Counters.Counter private _tokenIdCounter;

  struct Profile {
    string username;
    string metadata;
    uint256 timestamp;
    uint256 followPrice;
    uint256 consumedStars;
    uint256 followerCounter;
    address owner;
  }

  enum Variant {
    STAR,
    PROFILE,
    FOLLOW,
    PUBLICATION
  }

  struct FollowData {
    uint256 followId;
    uint256 follower;
    uint256 following;
    uint256 createdAt;
    address owner;
  }

  struct CollectSetting {
    uint256 price;
    uint256 supply;
    uint256 deadline;
    bool onlyFollowers;
  }

  struct Publication {
    uint256 publisher;
    string uri;
    uint256 commented;
    bool publicComment;
    bool publicMirror;
    bool starred;
    uint256 mirrored;
  }

  mapping(uint256 => Variant) public tokenVariant;

  mapping(uint256 => Profile) public profiles;
  mapping(bytes32 => uint256) public usernames;
  mapping(address => EnumerableSet.UintSet) private addressProfiles;
  /// A mapping that [target][follower] =>[tokenId]
  mapping(uint256 => mapping(uint256 => uint256)) private followingLists;
  mapping(uint256 => FollowData) private followsData;

  mapping(address => uint256) public balances;

  mapping(uint256 => Publication) public publications;
  mapping(uint256 => CollectSetting) public collectSettings;

  struct Bid {
    uint256 amount;
    address bidder;
    uint256 round;
    bool isClaimed;
  }

  Bid public currentBid;

  // Handle Star System
  // Handle Profiles
  // Handle Publications
  // Handle Followers

  constructor() ERC1155("") {
    _tokenIdCounter.increment();
    tokenVariant[0] = Variant.STAR;
    deployedAt = block.timestamp;
    manager = msg.sender;
  }

  function getCurrentRound() public view returns (uint256 currentRound) {
    currentRound = (block.timestamp - deployedAt) / BID_DURATION;
  }

  function bid(uint256 amount_) public payable {
    balances[msg.sender] += msg.value;
    require(balances[msg.sender] >= amount_, "not enough balance");
    balances[msg.sender] -= amount_;
    uint256 currentRound = getCurrentRound();
    if (
      currentBid.round < currentRound &&
      !currentBid.isClaimed &&
      currentBid.bidder != address(0)
    ) {
      claim();
    }
    require(amount_ >= currentBid.amount + BID_STEP, "not enough");
    if (currentBid.amount > 0 && !currentBid.isClaimed) {
      balances[currentBid.bidder] += currentBid.amount;
    }

    currentBid = Bid(amount_, msg.sender, currentRound, false);
    emit Bidded(msg.value, msg.sender, currentRound);
  }

  function claim() public {
    uint256 currentRound = getCurrentRound();
    require(
      currentBid.round < currentRound &&
        !currentBid.isClaimed &&
        currentBid.bidder != address(0),
      "not claimable"
    );
    balances[manager] += currentBid.amount;
    _mint(currentBid.bidder, STARS_ID, 1, "");
    currentBid = Bid(0, address(0), currentRound, false);
  }

  function consume(uint256 target_, uint256 amount_) public {
    Profile storage targetProfile = profiles[target_];
    _burn(msg.sender, STARS_ID, amount_);
    targetProfile.consumedStars += amount_;
    emit Consumed(target_, amount_);
  }

  function createProfile(
    string memory username_,
    string memory metadata_,
    uint256 followPrice_
  ) public {
    require(isUsernameAvailable(username_), "taken username.");
    uint256 profileId = _tokenIdCounter.current();
    _tokenIdCounter.increment();
    tokenVariant[profileId] = Variant.PROFILE;
    _mint(msg.sender, profileId, 1, "");
    profiles[profileId] = Profile(
      username_,
      metadata_,
      block.timestamp,
      followPrice_,
      0,
      0,
      msg.sender
    );
    usernames[keccak256(abi.encodePacked(username_))] = profileId;
    addressProfiles[msg.sender].add(profileId);
    emit ProfileCreated(
      profileId,
      username_,
      metadata_,
      followPrice_,
      msg.sender
    );
  }

  function editProfile(
    uint256 from_,
    string memory username_,
    string memory metadata_,
    uint256 followPrice_
  ) public {
    require(balanceOf(msg.sender, from_) > 0, "not owner");
    require(
      usernames[keccak256(abi.encodePacked(username_))] == 0 ||
        usernames[keccak256(abi.encodePacked(username_))] == from_,
      "Not available."
    );
    Profile storage userProfile = profiles[from_];
    if (
      keccak256(abi.encodePacked(userProfile.username)) !=
      keccak256(abi.encodePacked(username_))
    ) {
      usernames[keccak256(abi.encodePacked(userProfile.username))] = 0;
      usernames[keccak256(abi.encodePacked(username_))] = from_;
    }
    userProfile.username = username_;
    userProfile.metadata = metadata_;
    userProfile.followPrice = followPrice_;
    emit ProfileEdited(from_, username_, metadata_, followPrice_);
  }

  function isUsernameAvailable(
    string memory username_
  ) public view returns (bool) {
    if (usernames[keccak256(abi.encodePacked(username_))] == 0) {
      return true;
    } else {
      return false;
    }
  }

  // Get Address Profiles - View
  function getAdressProfiles(
    address target_
  ) public view returns (Profile[] memory) {
    Profile[] memory targetProfiles = new Profile[](
      addressProfiles[target_].length()
    );

    for (uint256 i = 0; i < addressProfiles[target_].length(); i++) {
      targetProfiles[i] = profiles[addressProfiles[target_].at(i)];
    }

    return targetProfiles;
  }

  // Get Profile - View
  // Follow a profile
  function followProfile(uint256 from_, uint256 target_) public payable {
    require(balanceOf(msg.sender, from_) > 0, "not owner");
    // Will do both follow and unfollow
    Profile storage targetProfile = profiles[target_];
    if (targetProfile.followPrice > 0) {
      require(msg.value == targetProfile.followPrice, "not price");
      balances[targetProfile.owner] = targetProfile.followPrice;
    }
    if (!isFollowed(from_, target_)) {
      uint256 tokenId = _tokenIdCounter.current();
      _mint(msg.sender, tokenId, 1, "");
      tokenVariant[tokenId] = Variant.FOLLOW;
      followsData[tokenId] = FollowData(
        targetProfile.followerCounter,
        from_,
        target_,
        block.timestamp,
        msg.sender
      );
      followingLists[target_][from_] = tokenId;
      emit Followed(
        from_,
        target_,
        block.timestamp,
        targetProfile.followerCounter,
        tokenId,
        true
      );
      targetProfile.followerCounter += 1;
      _tokenIdCounter.increment();
    } else {
      uint256 tokenId = followingLists[target_][from_];
      emit Followed(
        from_,
        target_,
        block.timestamp,
        followsData[tokenId].followId,
        tokenId,
        false
      );
      followsData[tokenId] = FollowData(0, 0, 0, 0, address(0));
      followingLists[target_][from_] = 0;
      _burn(msg.sender, tokenId, 1);
    }
  }

  function deactiveFollowNFT(uint256 from_, uint256 tokenId_) public {
    require(tokenVariant[tokenId_] == Variant.FOLLOW, "only follow");
    require(balanceOf(msg.sender, from_) > 0, "not owner");
    FollowData storage currentFollowData = followsData[tokenId_];
    require(currentFollowData.follower == from_, "not owner");
    if (balanceOf(msg.sender, tokenId_) == 0) {
      _safeTransferFrom(currentFollowData.owner, msg.sender, tokenId_, 1, "");
    }
    currentFollowData.follower = 0;
    emit FollowActivation(
      from_,
      currentFollowData.following,
      block.timestamp,
      currentFollowData.followId,
      tokenId_,
      false
    );
  }

  function activateFollowNFT(uint256 tokenId_, uint256 on_) public {
    require(tokenVariant[tokenId_] == Variant.FOLLOW, "only follow");
    require(balanceOf(msg.sender, on_) > 0, "not owner");
    require(balanceOf(msg.sender, tokenId_) > 0, "not owner");
    FollowData storage currentFollowData = followsData[tokenId_];
    require(currentFollowData.follower == 0, "not deactive");
    currentFollowData.follower = on_;
    emit FollowActivation(
      0,
      on_,
      block.timestamp,
      currentFollowData.followId,
      tokenId_,
      true
    );
  }

  // Is following the profile - View
  function isFollowed(
    uint256 follower_,
    uint256 target_
  ) public view returns (bool) {
    if (followingLists[target_][follower_] > 0) {
      return true;
    } else {
      return false;
    }
  }

  function withdraw(uint256 amount_) public {
    uint currentBalance = balances[msg.sender];
    require(amount_ <= currentBalance, "not enough balance");
    balances[msg.sender] -= amount_;
    (bool sent, ) = msg.sender.call{ value: amount_ }("");
    require(sent, "Failed to send");
    emit Withdrawal(msg.sender, amount_);
  }

  // Transfering Profile

  /// ========= PUBLICATION STUFFS =========== ///
  function publish(
    uint256 from_,
    string memory uri_,
    uint256 commented_,
    bool publicComment_,
    bool publicMirror_,
    bool starred_,
    CollectSetting memory collectSetting_
  ) public {
    require(balanceOf(msg.sender, from_) > 0, "not owner");
    if (commented_ > 0) {
      Publication memory commentedPub = publications[commented_];
      require(commentedPub.mirrored == 0, "can't comment");
      if (!commentedPub.publicComment) {
        require(isFollowed(from_, commentedPub.publisher), "not auth");
      }
    }
    if (starred_ == true) {
      _burn(msg.sender, STARS_ID, 1);
    }

    uint256 publicationId = _tokenIdCounter.current();
    _tokenIdCounter.increment();
        tokenVariant[publicationId] = Variant.PUBLICATION;

    publications[publicationId] = Publication(
      from_,
      uri_,
      commented_,
      publicComment_,
      publicMirror_,
      starred_,
      0
    );
    collectSettings[publicationId] = collectSetting_;
    emit Published(
      publicationId,
      from_,
      uri_,
      commented_,
      publicComment_,
      publicMirror_,
      starred_
    ); 
    emit CollectSetted(publicationId, collectSetting_.price, collectSetting_.supply, collectSetting_.deadline, collectSetting_.onlyFollowers);
  }

  function mirror(uint256 from_, uint256 mirrorId_) public {
    require(balanceOf(msg.sender, from_) > 0, "not owner");
    Publication memory mirroredPub = publications[mirrorId_];
    require(mirroredPub.mirrored == 0, "can't mirror");
    if (!mirroredPub.publicComment) {
      require(isFollowed(from_, mirroredPub.publisher), "not auth");
    }
    uint256 publicationId = _tokenIdCounter.current();
    _tokenIdCounter.increment();
        tokenVariant[publicationId] = Variant.PUBLICATION;

    publications[publicationId] = Publication(
      from_,
      "",
      0,
      false,
      false,
      false,
      mirrorId_
    );
    emit Mirrored(publicationId, from_, mirrorId_);
  }

  function collect(uint256 from_, uint256 collectId_) public payable {
    Publication memory collectPublication = publications[collectId_];
    CollectSetting memory collectSettings_ = collectSettings[collectId_];
    require(
      collectSettings_.supply < totalSupply(collectId_),
      "no supply"
    );
    require(
      collectSettings_.deadline >= block.timestamp ||
        collectSettings_.deadline == 0,
      "no time"
    );
    balances[msg.sender] += msg.value;
    require(
      balances[msg.sender] >= collectSettings_.price,
      "no balance"
    );
    if (collectSettings_.onlyFollowers) {
      require(isFollowed(from_, collectPublication.publisher), "not follower");
    }
    balances[msg.sender] -= collectSettings_.price;
    _mint(currentBid.bidder, collectId_, 1, "");
    emit Collected(collectId_, from_);
  }

  ///
  /**
   * Need to change balance of since all Follows belongs to profile owner at all times
   * Unless he sell them
   *
   * */
  function balanceOf(
    address account,
    uint256 id
  ) public view virtual override returns (uint256) {
    require(
      account != address(0),
      "ERC1155: address zero is not a valid owner"
    );
    if (tokenVariant[id] == Variant.FOLLOW) {
      if (followsData[id].follower == 0) {
        return super.balanceOf(account, id);
      } else {
        return balanceOf(account, followsData[id].follower);
      }
    }
    return super.balanceOf(account, id);
  }

  ///
  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) internal virtual override {
    for (uint256 i; i < ids.length; i++) {
      _processBeforeTokenTransfer(ids[i], to);
    }
  }

  function _processBeforeTokenTransfer(uint256 tokenId_, address to_) internal {
    if (tokenVariant[tokenId_] == Variant.FOLLOW) {
      FollowData storage currentFollowData = followsData[tokenId_];
      require(currentFollowData.follower == 0, "not deactive");
      currentFollowData.owner = to_;
    } else if (tokenVariant[tokenId_] == Variant.PROFILE) {
      addressProfiles[msg.sender].remove(tokenId_);
      addressProfiles[to_].add(tokenId_);
    }
  }

  event ProfileCreated(
    uint256 profileId_,
    string username_,
    string metadata_,
    uint256 followPrice_,
    address owner_
  );

  event ProfileEdited(
    uint256 profileId_,
    string username_,
    string metadata_,
    uint256 followPrice_
  );

  event Followed(
    uint256 from_,
    uint256 target_,
    uint256 at_,
    uint256 followId_,
    uint256 tokenId_,
    bool follow_
  );

  event FollowActivation(
    uint256 from_,
    uint256 target_,
    uint256 at_,
    uint256 followId_,
    uint256 tokenId_,
    bool active
  );

  event Withdrawal(address indexed user_, uint256 amount_);

  event Bidded(uint256 amount_, address bidder_, uint256 round_);
  event Claimed(address claimer_, uint256 round_);

  event Consumed(uint256 target_, uint256 amount_);

  event Published(
    uint256 publicationId_,
    uint256 from_,
    string uri_,
    uint256 commented_,
    bool publicComment_,
    bool publicMirror_,
    bool starred_
  );
  event CollectSetted(    uint256 publicationId_,uint256 price,
    uint256 supply,
    uint256 deadline,
    bool onlyFollowers
);

  event Mirrored(uint256 publicationId_, uint256 from_, uint256 mirrorId_);
  event Collected(uint256 collectId_, uint256 from_);
}
