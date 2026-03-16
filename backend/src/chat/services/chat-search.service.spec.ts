import { ChatSearchService } from './chat-search.service';

describe('ChatSearchService', () => {
  let service: ChatSearchService;
  let mockUsersService: any;
  let mockFriendsService: any;
  let mockClient: any;

  beforeEach(() => {
    mockUsersService = {
      findByUsernameAndTag: jest.fn(),
    };
    mockFriendsService = {
      getFriends: jest.fn().mockResolvedValue([]),
    };
    service = new ChatSearchService(mockUsersService, mockFriendsService);
    mockClient = {
      data: { user: { id: 1 } },
      emit: jest.fn(),
    };
  });

  it('should return empty if no user on client', async () => {
    mockClient.data = {};
    await service.handleSearchUsers(mockClient, { handle: 'alice#1234' });
    expect(mockClient.emit).not.toHaveBeenCalled();
  });

  it('should emit searchUsersResult with matching user', async () => {
    const foundUser = { id: 2, username: 'alice', tag: '1234', profilePictureUrl: null };
    mockUsersService.findByUsernameAndTag.mockResolvedValue(foundUser);
    mockFriendsService.getFriends.mockResolvedValue([]);

    await service.handleSearchUsers(mockClient, { handle: 'alice#1234' });

    expect(mockUsersService.findByUsernameAndTag).toHaveBeenCalledWith('alice', '1234');
    expect(mockClient.emit).toHaveBeenCalledWith('searchUsersResult', [
      expect.objectContaining({ id: 2, username: 'alice' }),
    ]);
  });

  it('should emit empty array when searching for self', async () => {
    const selfUser = { id: 1, username: 'myself', tag: '1001', profilePictureUrl: null };
    mockUsersService.findByUsernameAndTag.mockResolvedValue(selfUser);

    await service.handleSearchUsers(mockClient, { handle: 'myself#1001' });

    expect(mockClient.emit).toHaveBeenCalledWith('searchUsersResult', []);
  });

  it('should emit empty array when user not found', async () => {
    mockUsersService.findByUsernameAndTag.mockResolvedValue(null);

    await service.handleSearchUsers(mockClient, { handle: 'nobody#9999' });

    expect(mockClient.emit).toHaveBeenCalledWith('searchUsersResult', []);
  });

  it('should emit empty array when user is already a friend', async () => {
    const foundUser = { id: 2, username: 'alice', tag: '1234', profilePictureUrl: null };
    mockUsersService.findByUsernameAndTag.mockResolvedValue(foundUser);
    mockFriendsService.getFriends.mockResolvedValue([{ id: 2 }]);

    await service.handleSearchUsers(mockClient, { handle: 'alice#1234' });

    expect(mockClient.emit).toHaveBeenCalledWith('searchUsersResult', []);
  });

  it('should emit error on invalid handle format', async () => {
    await service.handleSearchUsers(mockClient, { handle: 'invalid' });

    expect(mockClient.emit).toHaveBeenCalledWith('error', {
      message: expect.stringContaining('Enter username#tag'),
    });
  });
});
